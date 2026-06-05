# frozen_string_literal: true

class AiAgents::Usage::Summary
  WARNING_REMAINING_RATIO = 0.2
  RECENT_EVENTS_LIMIT = 10

  def initialize(account:, now: Time.current, include_recent_events: false)
    @account = account
    @now = now
    @include_recent_events = include_recent_events
    @period = AiAgents::Usage::Period.new(account: account, now: now)
  end

  def payload
    {
      period: 'monthly',
      period_start_at: period.start_at.iso8601,
      period_end_at: period.end_at.iso8601,
      reset_at: period.reset_at.iso8601,
      limit: limit,
      used: used,
      remaining: remaining,
      unlimited: unlimited?,
      status: status,
      reuse_window_hours: account.ai_agent_conversation_reuse_window_hours,
      metrics: metrics
    }.tap do |data|
      data[:recent_events] = recent_events if include_recent_events
    end
  end

  private

  attr_reader :account, :now, :include_recent_events, :period

  def limit
    @limit ||= account.ai_agent_conversation_limit
  end

  def unlimited?
    limit.zero?
  end

  def used
    @used ||= current_events.consumed.count
  end

  def reserved
    @reserved ||= current_events.reserved.count
  end

  def active_used
    used + reserved
  end

  def remaining
    return nil if unlimited?

    [limit - active_used, 0].max
  end

  def status
    return 'unlimited' if unlimited?
    return 'exhausted' if remaining.zero?
    return 'warning' if remaining <= (limit * WARNING_REMAINING_RATIO).ceil

    'ok'
  end

  def metrics
    {
      counted_conversations: used,
      ai_replies: live_llm_calls.select(:message_id).distinct.count,
      tool_calls: live_tool_executions.count,
      handoffs: account.reporting_events.where(name: 'conversation_bot_handoff', created_at: period.start_at...period.end_at).count
    }
  end

  def current_events
    @current_events ||= account.ai_agent_usage_events.monthly.where(period_start_at: period.start_at)
  end

  def live_llm_calls
    @live_llm_calls ||= account.ai_agent_llm_calls.live.succeeded.where(created_at: period.start_at...period.end_at)
  end

  def live_tool_executions
    @live_tool_executions ||= account.ai_agent_tool_executions.live.where(created_at: period.start_at...period.end_at)
  end

  def recent_events
    current_events.consumed.includes(:conversation, :contact).reorder(created_at: :desc).limit(RECENT_EVENTS_LIMIT).map do |event|
      {
        id: event.id,
        conversation_id: event.conversation_id,
        conversation_display_id: event.conversation&.display_id,
        contact_id: event.contact_id,
        contact_name: event.contact&.name,
        window_started_at: event.window_started_at.iso8601,
        window_ends_at: event.window_ends_at.iso8601,
        created_at: event.created_at.iso8601
      }
    end
  end
end
