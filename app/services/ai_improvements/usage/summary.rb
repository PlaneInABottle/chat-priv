# frozen_string_literal: true

class AiImprovements::Usage::Summary
  WARNING_REMAINING_RATIO = 0.2
  RECENT_EVENTS_LIMIT = 20

  def initialize(account:, now: Time.current, include_recent_events: false)
    @account = account
    @now = now
    @include_recent_events = include_recent_events
    @period = AiAgents::Usage::Period.new(account: account, now: now)
  end

  def payload
    AiImprovements::Usage::Limiter.release_stale_reservations!(account: account, now: now)

    {
      period: 'monthly',
      period_start_at: period.start_at.iso8601,
      period_end_at: period.end_at.iso8601,
      reset_at: period.reset_at.iso8601,
      limit_credits: limit,
      used_credits: used,
      reserved_credits: reserved,
      remaining_credits: remaining,
      unlimited: unlimited?,
      status: status,
      breakdown: breakdown,
      rates: AiImprovements::Usage::Meter::UNITS_PER_CREDIT
    }.tap do |data|
      data[:recent_events] = recent_events if include_recent_events
    end
  end

  def exhausted?
    !unlimited? && remaining.zero?
  end

  private

  attr_reader :account, :now, :include_recent_events, :period

  def limit
    @limit ||= account.ai_improvement_monthly_credit_limit
  end

  def unlimited?
    limit.zero?
  end

  def used
    @used ||= current_events.consumed.sum(:credits)
  end

  def reserved
    @reserved ||= current_events.reserved.sum(:credits)
  end

  def remaining
    return nil if unlimited?

    [limit - used - reserved, 0].max
  end

  def status
    return 'unlimited' if unlimited?
    return 'exhausted' if remaining.zero?
    return 'warning' if remaining.fdiv(limit) <= WARNING_REMAINING_RATIO

    'ok'
  end

  def current_events
    @current_events ||= account.ai_improvement_usage_events.for_period(period.start_at)
  end

  def breakdown
    current_events.consumed.group(:operation).sum(:credits)
  end

  def recent_events
    current_events.consumed.reorder(created_at: :desc).limit(RECENT_EVENTS_LIMIT).map do |event|
      {
        id: event.id,
        operation: event.operation,
        unit_type: event.unit_type,
        units: event.units,
        credits: event.credits,
        created_at: event.created_at.iso8601
      }
    end
  end
end
