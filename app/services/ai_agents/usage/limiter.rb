# frozen_string_literal: true

class AiAgents::Usage::Limiter
  Result = Struct.new(:status, :event, :summary, keyword_init: true) do
    def allowed?
      %i[reserved reused unlimited].include?(status)
    end

    def reserved?
      status == :reserved
    end

    def exhausted?
      status == :exhausted
    end
  end

  def initialize(ai_agent:, message:, now: Time.current)
    @ai_agent = ai_agent
    @message = message
    @account = ai_agent.account
    @now = now
    @period = AiAgents::Usage::Period.new(account: account, now: now)
  end

  def reserve!
    return result(:unlimited) if unlimited?
    return result(:reused, event: reusable_event) if reusable_event

    account.with_lock do
      return result(:reused, event: reusable_event) if reusable_event
      return result(:exhausted) if active_usage_count >= limit

      event = account.ai_agent_usage_events.create!(
        ai_agent: ai_agent,
        contact: message.conversation.contact,
        conversation: message.conversation,
        message: message,
        period: :monthly,
        period_start_at: period.start_at,
        period_end_at: period.end_at,
        window_started_at: now,
        window_ends_at: window_ends_at,
        status: :reserved
      )
      result(:reserved, event: event)
    end
  end

  def consume!(event)
    return unless event

    event.with_lock do
      event.reload
      next if event.consumed?
      next unless event.reserved? || event.released?
      next unless same_usage_scope?(event)

      event.update!(successful_event_attributes.merge(status: :consumed))
    end
  end

  def release!(event)
    return unless event

    event.with_lock do
      event.reload
      next unless event.reserved?

      event.update!(status: :released)
    end
  end

  def exhausted_handoff!(summary:)
    conversation = message.conversation.reload
    return if handoff_completed?(conversation)

    add_private_note!(conversation, summary)
    conversation.update!(additional_attributes: current_additional_attributes(conversation).merge(exhausted_attributes(summary)))
    conversation.bot_handoff!
  end

  private

  attr_reader :ai_agent, :message, :account, :now, :period

  def limit
    @limit ||= account.ai_agent_conversation_limit
  end

  def unlimited?
    limit.zero?
  end

  def window_ends_at
    now + account.ai_agent_conversation_reuse_window_hours.hours
  end

  def reusable_event
    contact_id = message.conversation.contact_id
    return if contact_id.blank?

    @reusable_event ||= AiAgentUsageEvent
                        .active_for_contact_window(account_id: account.id, contact_id: contact_id, at: now)
                        .monthly
                        .where(period_start_at: period.start_at)
                        .reorder(window_ends_at: :desc)
                        .first
  end

  def same_usage_scope?(event)
    event.account_id == account.id && event.contact_id == message.conversation.contact_id
  end

  def successful_event_attributes
    {
      ai_agent: ai_agent,
      contact: message.conversation.contact,
      conversation: message.conversation,
      message: message
    }
  end

  def active_usage_count
    account.ai_agent_usage_events.active.monthly.where(period_start_at: period.start_at).count
  end

  def result(status, event: nil)
    Result.new(status: status, event: event, summary: summary_payload)
  end

  def summary_payload
    AiAgents::Usage::Summary.new(account: account, now: now).payload
  end

  def add_private_note!(conversation, summary)
    Messages::MessageBuilder.new(nil, conversation, {
                                   content: exhausted_note(summary),
                                   private: true,
                                   sender_type: 'AgentBot',
                                   sender_id: ai_agent.agent_bot_id
                                 }).perform
  end

  def exhausted_note(summary)
    reset_at = Time.zone.parse(summary[:reset_at]).in_time_zone(account.reporting_timezone.presence || Time.zone.name)
    "AI Asistan monthly conversation limit is exhausted. AI will not reply until #{reset_at.strftime('%Y-%m-%d %H:%M %Z')}."
  end

  def exhausted_attributes(summary)
    {
      'ai_handoff_completed' => true,
      'ai_handoff_at' => Time.current.iso8601(3),
      'ai_handoff_by_ai_agent_id' => ai_agent.id,
      'ai_handoff_message_id' => message.id,
      'ai_handoff_reason' => 'ai_usage_limit_exhausted',
      'ai_usage_limit_exhausted' => true,
      'ai_usage_limit_reset_at' => summary[:reset_at]
    }
  end

  def handoff_completed?(conversation)
    current_additional_attributes(conversation)['ai_handoff_completed'] == true
  end

  def current_additional_attributes(conversation)
    conversation.additional_attributes.is_a?(Hash) ? conversation.additional_attributes.deep_stringify_keys : {}
  end
end
