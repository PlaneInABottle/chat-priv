class Voice::Livekit::StaleCallFinalizer
  DEFAULT_MINIMUM_AGE = 3.minutes
  DEFAULT_FALLBACK_TIMEOUT = 1.hour

  def self.perform!(account: nil, minimum_age: DEFAULT_MINIMUM_AGE, fallback_timeout: DEFAULT_FALLBACK_TIMEOUT)
    new(account: account, minimum_age: minimum_age, fallback_timeout: fallback_timeout).perform!
  end

  def self.finalize_call_if_stale!(call, minimum_age: DEFAULT_MINIMUM_AGE, fallback_timeout: DEFAULT_FALLBACK_TIMEOUT)
    new(minimum_age: minimum_age, fallback_timeout: fallback_timeout).finalize_call_if_stale!(call)
  end

  def initialize(account: nil, minimum_age: DEFAULT_MINIMUM_AGE, fallback_timeout: DEFAULT_FALLBACK_TIMEOUT)
    @account = account
    @minimum_age = minimum_age
    @fallback_timeout = fallback_timeout
  end

  def perform!
    stale_candidates.filter_map { |call| finalize_call_if_stale!(call) }
  end

  def finalize_call_if_stale!(call)
    return if call.terminal?
    return finalize_max_duration!(call) if max_duration_exceeded?(call)
    return unless old_enough?(call, minimum_age)

    summary = Voice::Livekit::RoomService.participant_summary(call: call)
    reason = stale_reason(call, summary)
    return unless reason

    call.update!(meta: (call.meta || {}).merge('livekit_stale_check' => summary.merge('ended_reason' => reason)))
    Voice::CallFinalizer.perform!(call: call, end_reason: reason)
    call
  end

  private

  attr_reader :account, :minimum_age, :fallback_timeout

  def stale_candidates
    scope = Call.where(provider: :livekit).active.where.not(started_at: nil)
    scope = scope.where(account: account) if account
    scope
  end

  def finalize_max_duration!(call)
    Voice::CallFinalizer.perform!(call: call, end_reason: 'voice_max_duration_exceeded')
    call
  end

  def max_duration_exceeded?(call)
    return false unless call.started_at

    call.started_at <= call.account.voice_ai_max_call_duration_minutes.minutes.ago
  end

  def stale_reason(call, summary)
    case summary['status']
    when 'active'
      'livekit_no_customer_participants' if summary['customer_participant_count'].to_i.zero?
    when 'not_found'
      'livekit_room_not_found'
    when 'skipped', 'failed'
      'stale_timeout' if old_enough?(call, fallback_timeout)
    end
  end

  def old_enough?(call, age)
    call.started_at.present? && call.started_at < age.ago
  end
end
