# frozen_string_literal: true

class AiImprovements::Usage::Limiter
  RESERVATION_TTL = 1.hour

  Result = Struct.new(:status, :event, :summary, keyword_init: true) do
    def allowed?
      %i[reserved consumed].include?(status)
    end

    def exhausted?
      status == :exhausted
    end
  end

  # The optional records make a usage event traceable to the feature that initiated it.
  def initialize(account:, operation:, ai_agent: nil, voice_agent: nil, initiated_by: nil, now: Time.current) # rubocop:disable Metrics/ParameterLists
    @account = account
    @operation = operation.to_s
    @ai_agent = ai_agent
    @voice_agent = voice_agent
    @initiated_by = initiated_by
    @now = now
    @period = AiAgents::Usage::Period.new(account: account, now: now)
  end

  def reserve!(unit_type: 'tokens', credits: 1, idempotency_key: SecureRandom.uuid, metadata: {})
    requested_credits = normalize_requested_credits(credits)
    account.with_lock do
      release_stale_reservations!
      existing = current_period_event(idempotency_key)
      next reserve_existing(existing, unit_type: unit_type, credits: requested_credits, metadata: metadata) if existing
      next result(:exhausted) unless enough_credits?(requested_credits)

      result(:reserved, event: create_reservation(unit_type, requested_credits, idempotency_key, metadata))
    end
  end

  def reserve_or_raise!(**attributes)
    reservation = reserve!(**attributes)
    raise AiImprovements::Usage::Exhausted, reservation.summary if reservation.exhausted?

    reservation.event
  end

  def ensure_available!
    account.with_lock do
      release_stale_reservations!
      current_summary = summary
      raise AiImprovements::Usage::Exhausted, current_summary.payload if current_summary.exhausted?

      current_summary.payload
    end
  end

  def consume!(event, unit_type:, units:, metadata: {})
    return unless event&.account_id == account.id

    event.with_lock do
      event.reload
      next event if event.consumed?
      next event unless event.reserved?

      event.update!(
        status: :consumed,
        unit_type: unit_type,
        units: [units.to_f.ceil, 0].max,
        credits: AiImprovements::Usage::Meter.credits_for(unit_type: unit_type, units: units),
        metadata: event.metadata.to_h.merge(metadata.to_h)
      )
      event
    end
  end

  def release!(event)
    return unless event&.account_id == account.id

    event.with_lock do
      event.reload
      event.update!(status: :released) if event.reserved?
    end
  end

  private

  attr_reader :account, :operation, :ai_agent, :voice_agent, :initiated_by, :now, :period

  def summary
    AiImprovements::Usage::Summary.new(account: account, now: now)
  end

  def result(status, event: nil)
    Result.new(status: status, event: event, summary: summary.payload)
  end

  def normalize_requested_credits(credits)
    parsed = Integer(credits, exception: false)
    raise ArgumentError, 'credits must be a positive integer' unless parsed&.positive?

    parsed
  end

  def enough_credits?(requested_credits)
    payload = summary.payload
    payload[:unlimited] || payload[:remaining_credits] >= requested_credits
  end

  def current_period_event(idempotency_key)
    account.ai_improvement_usage_events.find_by(
      period_start_at: period.start_at,
      idempotency_key: idempotency_key
    )
  end

  def reserve_existing(event, unit_type:, credits:, metadata:)
    return result(event.status.to_sym, event: event) unless event.released?
    return result(:exhausted) unless enough_credits?(credits)

    event.update!(
      status: :reserved,
      unit_type: unit_type,
      units: 0,
      credits: credits,
      metadata: event.metadata.to_h.merge(metadata.to_h),
      updated_at: now
    )
    result(:reserved, event: event)
  end

  def create_reservation(unit_type, credits, idempotency_key, metadata)
    account.ai_improvement_usage_events.create!(
      ai_agent: ai_agent,
      voice_agent: voice_agent,
      initiated_by: initiated_by,
      operation: operation,
      unit_type: unit_type,
      units: 0,
      credits: credits,
      status: :reserved,
      period_start_at: period.start_at,
      period_end_at: period.end_at,
      idempotency_key: idempotency_key,
      metadata: metadata
    )
  end

  def release_stale_reservations!
    account.ai_improvement_usage_events.reserved.where('updated_at < ?', now - RESERVATION_TTL).find_each do |event|
      next if linked_call_active?(event)

      event.update!(status: :released)
    end
  end

  def linked_call_active?(event)
    event.call.present? && !event.call.terminal?
  end
end
