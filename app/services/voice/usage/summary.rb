class Voice::Usage::Summary
  WARNING_REMAINING_RATIO = 0.2

  def initialize(account:, now: Time.current)
    @account = account
    @now = now
    @period = AiAgents::Usage::Period.new(account: account, now: now)
  end

  def payload
    {
      period: 'monthly',
      period_start_at: period.start_at.iso8601,
      period_end_at: period.end_at.iso8601,
      reset_at: period.reset_at.iso8601,
      enabled: account.voice_ai_enabled?,
      limit_minutes: limit_minutes,
      used_minutes: used_minutes,
      remaining_minutes: remaining_minutes,
      unlimited: unlimited?,
      status: status,
      max_call_duration_minutes: account.voice_ai_max_call_duration_minutes,
      concurrent_call_limit: account.voice_ai_concurrent_call_limit,
      active_calls: active_calls,
      metrics: metrics
    }
  end

  def limit_minutes
    @limit_minutes ||= account.voice_ai_monthly_minute_limit
  end

  def unlimited?
    limit_minutes.zero?
  end

  def used_minutes
    @used_minutes ||= completed_real_calls.sum('CEIL(duration_seconds / 60.0)').to_i
  end

  def remaining_minutes
    return nil if unlimited?

    [limit_minutes - used_minutes, 0].max
  end

  def active_calls
    @active_calls ||= real_livekit_calls.active.count
  end

  private

  attr_reader :account, :now, :period

  def status
    return 'disabled' unless account.voice_ai_enabled?
    return 'unlimited' if unlimited?
    return 'exhausted' if remaining_minutes.zero?
    return 'warning' if remaining_minutes <= (limit_minutes * WARNING_REMAINING_RATIO).ceil

    'ok'
  end

  def metrics
    {
      real_calls: completed_real_calls.count,
      test_calls: test_livekit_calls.where(created_at: period.start_at...period.end_at).count,
      total_duration_seconds: total_duration_seconds,
      average_call_seconds: average_call_seconds
    }
  end

  def completed_real_calls
    @completed_real_calls ||= real_livekit_calls
                              .where(status: Call::TERMINAL_STATUSES)
                              .where('duration_seconds > 0')
                              .where(started_at: period.start_at...period.end_at)
  end

  def real_livekit_calls
    @real_livekit_calls ||= account.calls.livekit.where.not("COALESCE(calls.meta->>'test_call', 'false') = 'true'")
  end

  def test_livekit_calls
    @test_livekit_calls ||= account.calls.livekit.where("COALESCE(calls.meta->>'test_call', 'false') = 'true'")
  end

  def total_duration_seconds
    @total_duration_seconds ||= completed_real_calls.sum(:duration_seconds).to_i
  end

  def average_call_seconds
    real_call_count = completed_real_calls.count
    return 0 if real_call_count.zero?

    (total_duration_seconds.to_f / real_call_count).round
  end
end
