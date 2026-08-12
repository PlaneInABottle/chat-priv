# rubocop:disable Metrics/ClassLength
class AiAgents::LiveProcessor
  HISTORY_MESSAGE_LIMIT = 20
  RAW_HISTORY_MESSAGE_LIMIT = HISTORY_MESSAGE_LIMIT * AiAgents::Tools::PresentCatalogProductsService::MAX_PRODUCTS

  def initialize(message:, adapter: nil, media_preparer: nil)
    @message = message
    @adapter = adapter
    @media_preparer = media_preparer
  end

  def perform
    return unless eligible_message? && reply_gate_allows?
    return false if response_already_persisted?

    usage_result = usage_limiter.reserve!
    return handle_usage_exhausted!(usage_result) if usage_result.exhausted?

    window_result = response_window.reserve!(event: usage_result.event, trigger_message_id: message.id)
    return handle_response_limit_exhausted!(window_result) if window_result.exhausted?

    persist_or_consume!(orchestrator_result, usage_result, window_result)
  rescue StandardError
    rollback_reservations!(usage_result, window_result)
    raise
  end

  private

  attr_reader :message, :adapter

  def conversation
    message.conversation
  end

  def ai_agent
    @ai_agent ||= conversation.assignee_agent_bot&.ai_agent || conversation.inbox.agent_bot&.ai_agent
  end

  def pinned_release
    @pinned_release ||= AiAgents::ReleaseResolver.for(conversation: conversation, ai_agent: ai_agent)
  end

  def eligible_message?
    ai_agent&.enabled? && ai_agent.account.ai_agent_enabled? && eligible_customer_message?
  end

  def eligible_customer_message?
    message.incoming? && message.text? && !message.private? && !message.activity? && !message.template?
  end

  def reply_gate_allows?
    return true if AiAgents::ReplyPolicy.can_reply?(conversation)

    skip_reason = "conversation=#{conversation.id} status=#{conversation.status} handoff=#{AiAgents::ReplyPolicy.handoff_completed?(conversation)}"
    Rails.logger.info("[AiAgents] Reply skipped: #{skip_reason}")
    false
  end

  def orchestrator_messages
    messages = recent_messages.map do |entry|
      message = {
        role: entry.message_type == 'incoming' ? 'user' : 'assistant',
        content: entry.content_for_llm
      }
      presentation = entry.content_attributes.dig('ai_agent', 'catalog_presentation')
      message[:catalog_presentation] = presentation if presentation.present?
      message
    end
    AiAgents::ConversationHistoryProjector.new(AiAgents::ConversationHistoryCompactor.new(messages).call.last(HISTORY_MESSAGE_LIMIT)).call
  end

  def orchestrator_result
    AiAgents::Orchestrator.new(
      ai_agent: ai_agent,
      messages: orchestrator_messages,
      mode: :live,
      conversation: conversation,
      trigger_message: message,
      adapter: adapter,
      prompt_override: pinned_release&.prompt,
      config_override: pinned_release&.config,
      knowledge_sources_override: pinned_knowledge_sources
    ).perform
  end

  def pinned_knowledge_sources
    Array(pinned_release&.snapshot&.to_h&.fetch('knowledge_sources', []))
  end

  def recent_messages
    conversation.messages
                .where(private: false, message_type: %i[incoming outgoing])
                .where(id: ..message.id)
                .reorder(id: :desc)
                .limit(RAW_HISTORY_MESSAGE_LIMIT)
                .to_a
                .reverse
                .reject { |entry| entry.content_for_llm.blank? }
  end

  def post_assistant_message!(assistant_message)
    return if assistant_message.blank?

    Messages::MessageBuilder.new(nil, conversation.reload, assistant_message_params(assistant_message)).perform
  end

  def persist_assistant_response!(result, usage_result, window_result)
    return persist_catalog_product_response!(result, usage_result, window_result) if catalog_product_result?(result)

    conversation.with_lock do
      if result[:assistant_message].present? && !response_already_persisted?
        # A reused execution must re-assert its window capacity before the
        # public reply becomes visible; a blank result never consumes a slot.
        return false unless reclaim_window_capacity!(usage_result, window_result)

        post_assistant_message!(result[:assistant_message])
      end
      consume_usage!(usage_result, result, window_result)
    end
  end

  def persist_catalog_product_response!(result, usage_result, window_result)
    return false unless reclaim_window_capacity!(usage_result, window_result)

    prepared_messages = catalog_presentation_builder(result.fetch(:assistant_message)).call
    conversation.with_lock do
      unless response_already_persisted?
        prepared_messages.each do |message_spec|
          Messages::MessageBuilder.new(nil, conversation.reload, message_spec.fetch(:message_params)).perform
        end
      end
      consume_usage!(usage_result, result, window_result)
    end
  ensure
    prepared_messages&.each { |message_spec| message_spec[:prepared_image]&.close! }
  end

  def catalog_presentation_builder(assistant_message)
    AiAgents::CatalogPresentationBuilder.new(
      assistant_message: assistant_message,
      ai_agent: ai_agent,
      conversation: conversation,
      trigger_message_id: message.id,
      media_preparer: @media_preparer
    )
  end

  def response_already_persisted?
    conversation.messages.outgoing
                .where(private: false, sender: ai_agent.agent_bot)
                .where('id > ?', message.id)
                .any? do |reply|
      reply.content_attributes.dig('ai_agent', 'trigger_message_id').to_i == message.id
    end
  end

  def usage_limiter
    @usage_limiter ||= AiAgents::Usage::Limiter.new(ai_agent: ai_agent, message: message)
  end

  def response_window
    @response_window ||= AiAgents::ResponseWindow.new(ai_agent: ai_agent, message: message)
  end

  def handle_usage_exhausted!(usage_result)
    usage_limiter.exhausted_handoff!(summary: usage_result.summary)
    true
  end

  def handle_response_limit_exhausted!(window_result)
    response_window.exhausted_handoff!(event: window_result.event, conversation: conversation, trigger_message_id: message.id)
    true
  end

  # Persists the assistant response (or consumes the handoff turn) and returns
  # whether the turn ended in a human handoff.
  def persist_or_consume!(result, usage_result, window_result)
    if handoff_result?(result)
      consume_usage!(usage_result, result, window_result)
    else
      persist_assistant_response!(result, usage_result, window_result)
    end

    handoff_result?(result)
  end

  # Release decisions are keyed on the result status, never on the slot row's
  # own state: only the execution that actually reserved the slot may release
  # it. A `:reused` execution holds no reservation, so its failure or blank
  # result must not cancel the owning execution's reservation out from under it.
  def rollback_reservations!(usage_result, window_result)
    response_window.release!(event: usage_result.event, slot: window_result&.slot) if window_result&.reserved?
    usage_limiter.release!(usage_result&.event) if usage_result&.reserved?
  end

  # A reused execution holds no capacity of its own: its slot row may have been
  # released by the owning execution while the LLM ran. Re-assert the slot under
  # the event lock (consuming it while capacity remains) before the public reply
  # becomes visible, so a released slot whose capacity was taken by other
  # triggers can never produce an over-limit customer-visible response.
  def reclaim_window_capacity!(usage_result, window_result)
    return true unless window_result&.reused? && window_result.slot

    response_window.consume!(event: usage_result.event, slot: window_result.slot) != :exhausted
  end

  def consume_usage!(usage_result, result, window_result)
    return unless usage_result&.event

    if result[:assistant_message].present? || handoff_result?(result)
      usage_limiter.consume!(usage_result.event)
      response_window.consume!(event: usage_result.event, slot: window_result&.slot) if window_result&.slot
      true
    else
      # Blank/unusable result: the monthly event is released only when this job
      # created it, and the response slot only when this job reserved it — a
      # reused execution must never release a slot it does not own.
      usage_limiter.release!(usage_result.event) if usage_result.reserved?
      response_window.release!(event: usage_result.event, slot: window_result&.slot) if window_result&.reserved?
      false
    end
  end

  def assistant_message_params(assistant_message)
    params = {
      content: assistant_message['content'] || assistant_message[:content],
      private: false,
      sender_type: 'AgentBot',
      sender_id: ai_agent.agent_bot_id,
      content_attributes: assistant_message_content_attributes(assistant_message)
    }
    presentation = assistant_message.dig('tool_result', 'presentation') || assistant_message.dig(:tool_result, :presentation)
    params[:content_type] = presentation['content_type'] || presentation[:content_type] if presentation.present?
    params
  end

  def assistant_message_content_attributes(assistant_message)
    telemetry = assistant_message['turn_telemetry'] || assistant_message[:turn_telemetry]
    source_attributions = assistant_message['source_attributions'] || assistant_message[:source_attributions]
    presentation = assistant_message.dig('tool_result', 'presentation') || assistant_message.dig(:tool_result, :presentation)
    attributes = { ai_agent: { trigger_message_id: message.id } }
    if presentation.present?
      attributes[:items] = presentation['items'] || presentation[:items]
      attributes[:ai_agent][:selection] = { version: 1 }
    end
    return attributes if telemetry.blank? && source_attributions.blank?

    attributes.deep_merge(
      ai_agent: {
        turn_telemetry: telemetry,
        source_attributions: source_attributions
      }.compact
    )
  end

  def handoff_result?(result)
    result[:terminal_action] == 'handoff'
  end

  def catalog_product_result?(result)
    result[:terminal_action] == AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL
  end
end
# rubocop:enable Metrics/ClassLength
