# frozen_string_literal: true

# Per-window reservation state machine for customer-visible AI responses.
# One slot row per (usage event, trigger message); all transitions run under the
# usage event row lock so concurrent jobs can never exceed the effective limit.
class AiAgents::ResponseWindow
  Result = Struct.new(:status, :event, :slot, keyword_init: true) do
    def reserved?
      status == :reserved
    end

    def reused?
      status == :reused
    end

    def exhausted?
      status == :exhausted
    end

    def inactive?
      status == :inactive
    end
  end

  def initialize(ai_agent:, message:)
    @ai_agent = ai_agent
    @message = message
    @account = ai_agent.account
  end

  def limit
    @limit ||= account.effective_ai_agent_response_limit_per_window
  end

  # Warning fires exactly when the consumed count reaches `limit - 5`; limits of
  # 5 or less never warn (remaining is always 5 by construction).
  def warning_threshold
    limit > 5 ? limit - 5 : 0
  end

  def reserve!(event:, trigger_message_id: message.id)
    return result(:inactive, event: event) unless event && limit.positive?

    event.with_lock do
      slot = event.response_slots.find_or_initialize_by(trigger_message_id: trigger_message_id)
      # A trigger whose terminal handoff was already delivered must never run again.
      return result(:exhausted, event: event) if handed_off_marker?(slot)

      # A released retry atomically re-reserves under the event lock while
      # capacity exists; only an exhausted released row stays untouched.
      released_result = released_retry_reserve!(event, slot)
      return released_result if released_result

      # Duplicate/retried jobs transition the same row idempotently.
      return result(:reused, event: event, slot: slot) if slot.persisted?

      return result(:exhausted, event: event) if event.response_slots.active.count >= limit

      slot.update!(status: :reserved)
      result(:reserved, event: event, slot: slot)
    end
  end

  # Consumes an owned reservation. Returns :consumed when the slot is (already)
  # consumed, :exhausted when a released retry can no longer be reclaimed because
  # other triggers filled the window, and nil for terminal handed_off markers.
  # A released slot is only consumed after re-asserting capacity under the event
  # lock: a stale execution that holds a `:reused` result (no reservation of its
  # own) must never push the window past its limit.
  def consume!(event:, slot:)
    return unless event && slot

    event.with_lock do
      slot.reload
      return :consumed if slot.consumed?
      return unless slot.reserved? || slot.released?
      return :exhausted if released_retry_denied?(event, slot)

      slot.update!(status: :consumed)
      maybe_send_warning!(event)
      :consumed
    end
  end

  def release!(event:, slot:)
    return unless event && slot

    event.with_lock do
      slot.reload
      slot.update!(status: :released) if slot.reserved?
    end
  end

  # Delivers the deterministic terminal handoff for a would-be (limit+1)th trigger.
  # Lock order is conversation -> event (invariant); the in-lock handoff re-check
  # makes same-conversation boundary races produce exactly one public delivery,
  # and the handed_off marker makes duplicate/retried triggers exactly-once.
  def exhausted_handoff!(event:, conversation:, trigger_message_id:)
    conversation.reload.with_lock do
      return false if AiAgents::ReplyPolicy.handoff_completed?(conversation)

      event.with_lock do
        event.reload
        marker = event.response_slots.find_or_initialize_by(trigger_message_id: trigger_message_id)
        return false if marker.persisted?

        marker.update!(status: :handed_off)
        deliver_terminal!(event: event, conversation: conversation, trigger_message_id: trigger_message_id)
        true
      end
    end
  end

  private

  attr_reader :ai_agent, :message, :account

  # A released retry becomes active again only while capacity remains: the row
  # is re-reserved under the event lock so concurrent released retries can never
  # both pass the capacity check and later consume beyond the limit.
  def released_retry_reserve!(event, slot)
    return unless slot.persisted? && slot.released?

    return result(:exhausted, event: event, slot: slot) if window_full?(event)

    slot.update!(status: :reserved)
    result(:reserved, event: event, slot: slot)
  end

  def window_full?(event)
    event.response_slots.active.count >= limit
  end

  # A released slot is only consumed after re-asserting capacity under the event
  # lock: a stale execution holding a `:reused` result (no reservation of its
  # own) must never push the window past its limit.
  def released_retry_denied?(event, slot)
    slot.released? && window_full?(event)
  end

  def handed_off_marker?(slot)
    slot.persisted? && slot.handed_off?
  end

  def maybe_send_warning!(event)
    return if warning_threshold.zero?
    return if event.response_limit_warning_sent?
    return unless event.response_slots.consumed.count == warning_threshold

    event.update!(response_limit_warning_sent: true)
    persist_warning_message!(event)
  end

  def persist_warning_message!(event)
    Messages::MessageBuilder.new(nil, message.conversation, {
                                   content: I18n.t('ai_agents.response_limit_warning', locale: account.locale),
                                   private: false,
                                   sender_type: 'AgentBot',
                                   sender_id: ai_agent.agent_bot_id,
                                   content_attributes: {
                                     ai_agent: {
                                       system_notice: { type: 'response_limit_warning', limit: limit, remaining: 5 }
                                     }
                                   }
                                 }).perform
    Rails.logger.info("[AiAgents] Response limit warning: event=#{event.id} conversation=#{message.conversation_id} limit=#{limit}")
  end

  def deliver_terminal!(event:, conversation:, trigger_message_id:)
    used = event.response_slots.consumed.count
    persist_terminal_public_message!(conversation)
    persist_terminal_private_note!(conversation, event: event, used: used)
    conversation.update!(
      additional_attributes: current_additional_attributes(conversation).merge(terminal_attributes(trigger_message_id))
    )
    conversation.bot_handoff!
    Rails.logger.info(
      "[AiAgents] Response limit handoff: event=#{event.id} conversation=#{conversation.id} trigger=#{trigger_message_id} " \
      "limit=#{limit} used=#{used}"
    )
  end

  def persist_terminal_public_message!(conversation)
    Messages::MessageBuilder.new(nil, conversation, {
                                   content: I18n.t('ai_agents.response_limit_handoff_message', locale: account.locale),
                                   private: false,
                                   sender_type: 'AgentBot',
                                   sender_id: ai_agent.agent_bot_id,
                                   content_attributes: {
                                     ai_agent: { system_notice: { type: 'response_limit_handoff', limit: limit } }
                                   }
                                 }).perform
  end

  def persist_terminal_private_note!(conversation, event:, used:)
    Messages::MessageBuilder.new(nil, conversation, {
                                   content: I18n.t('ai_agents.response_limit_handoff_note',
                                                   locale: account.locale,
                                                   limit: limit,
                                                   used: used,
                                                   reset_at: reset_at_text(event)),
                                   private: true,
                                   sender_type: 'AgentBot',
                                   sender_id: ai_agent.agent_bot_id
                                 }).perform
  end

  def reset_at_text(event)
    zone = account.reporting_timezone.presence || Time.zone.name
    event.window_ends_at.in_time_zone(zone).strftime('%Y-%m-%d %H:%M %Z')
  end

  def terminal_attributes(trigger_message_id)
    {
      'ai_handoff_completed' => true,
      'ai_handoff_at' => Time.current.iso8601(3),
      'ai_handoff_by_ai_agent_id' => ai_agent.id,
      'ai_handoff_message_id' => trigger_message_id,
      'ai_handoff_reason' => 'ai_response_limit_exhausted',
      'ai_response_limit_exhausted' => true
    }
  end

  def current_additional_attributes(conversation)
    conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes.deep_stringify_keys : {}
  end

  def result(status, event:, slot: nil)
    Result.new(status: status, event: event, slot: slot)
  end
end
