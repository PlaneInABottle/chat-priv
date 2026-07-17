class AiAgents::LiveProcessor
  HANDOFF_COMPLETED_KEY = 'ai_handoff_completed'.freeze
  HISTORY_MESSAGE_LIMIT = 12

  def initialize(message:, adapter: nil)
    @message = message
    @adapter = adapter
  end

  def perform
    return unless eligible_message?
    return if handoff_completed?
    return false if response_already_persisted?

    usage_result = usage_limiter.reserve!
    return handle_usage_exhausted!(usage_result) if usage_result.exhausted?

    result = orchestrator_result

    if handoff_result?(result)
      consume_usage!(usage_result, result)
    else
      persist_assistant_response!(result, usage_result)
    end

    handoff_result?(result)
  rescue StandardError
    usage_limiter.release!(usage_result&.event) if usage_result&.reserved?
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
    message.incoming? && message.text? && !message.private? && !message.activity? && !message.template? && !ai_generated_message?
  end

  def ai_generated_message?
    message.outgoing? && message.sender_type.in?(['AgentBot', 'Captain::Assistant'])
  end

  def handoff_completed?
    attrs = conversation.additional_attributes
    attrs.is_a?(Hash) && attrs[HANDOFF_COMPLETED_KEY] == true
  end

  def orchestrator_messages
    recent_messages.map do |entry|
      {
        role: entry.message_type == 'incoming' ? 'user' : 'assistant',
        content: entry.content_for_llm
      }
    end
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
                .limit(HISTORY_MESSAGE_LIMIT)
                .to_a
                .reverse
                .reject { |entry| entry.content_for_llm.blank? }
  end

  def post_assistant_message!(assistant_message)
    return if assistant_message.blank?

    Messages::MessageBuilder.new(nil, conversation.reload, assistant_message_params(assistant_message)).perform
  end

  def persist_assistant_response!(result, usage_result)
    conversation.with_lock do
      post_assistant_message!(result[:assistant_message]) unless response_already_persisted?
      consume_usage!(usage_result, result)
    end
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

  def handle_usage_exhausted!(usage_result)
    usage_limiter.exhausted_handoff!(summary: usage_result.summary)
    true
  end

  def consume_usage!(usage_result, result)
    return unless usage_result&.event

    if result[:assistant_message].present? || handoff_result?(result)
      usage_limiter.consume!(usage_result.event)
    elsif usage_result.reserved?
      usage_limiter.release!(usage_result.event)
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
end
