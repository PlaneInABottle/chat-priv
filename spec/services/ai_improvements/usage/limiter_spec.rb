require 'rails_helper'

RSpec.describe AiImprovements::Usage::Limiter do
  let(:now) { Time.zone.parse('2026-07-11 12:00:00 UTC') }
  let(:account) do
    create(:account, settings: { ai_improvement_monthly_credit_limit: 3, reporting_timezone: 'Etc/UTC' })
  end
  let(:limiter) { described_class.new(account: account, operation: 'evaluation', now: now) }

  it 'reserves one credit and replaces it with actual metered usage' do
    event = limiter.reserve_or_raise!(idempotency_key: 'evaluation:1')

    expect(event).to have_attributes(status: 'reserved', credits: 1, units: 0)

    limiter.consume!(event, unit_type: 'tokens', units: 1_001)

    expect(event.reload).to have_attributes(status: 'consumed', credits: 2, units: 1_001)
  end

  it 're-reserves a released idempotent operation without creating a duplicate' do
    event = limiter.reserve_or_raise!(idempotency_key: 'evaluation:retry')
    limiter.release!(event)

    expect do
      retried = limiter.reserve_or_raise!(idempotency_key: 'evaluation:retry')
      expect(retried).to eq(event)
      expect(retried).to be_reserved
    end.not_to change(AiImprovementUsageEvent, :count)
  end

  it 'counts in-progress reservations when enforcing the account limit' do
    3.times { |index| limiter.reserve_or_raise!(idempotency_key: "evaluation:#{index}") }

    expect do
      limiter.reserve_or_raise!(idempotency_key: 'evaluation:blocked')
    end.to raise_error(AiImprovements::Usage::Exhausted) { |error| expect(error.summary[:remaining_credits]).to eq(0) }
  end

  it 'atomically rejects a reservation larger than the remaining balance' do
    limiter.reserve_or_raise!(credits: 2, idempotency_key: 'evaluation:large')

    expect do
      limiter.reserve_or_raise!(credits: 2, idempotency_key: 'evaluation:too-large')
    end.to raise_error(AiImprovements::Usage::Exhausted)

    expect(AiImprovementUsageEvent.reserved.sum(:credits)).to eq(2)
  end

  it 'releases stale reservations before admitting new work' do
    stale_limiter = described_class.new(account: account, operation: 'evaluation', now: now - 2.hours)
    stale_event = travel_to(now - 2.hours) do
      stale_limiter.reserve_or_raise!(idempotency_key: 'evaluation:stale')
    end
    2.times { |index| limiter.reserve_or_raise!(idempotency_key: "evaluation:current:#{index}") }

    expect(limiter.reserve_or_raise!(idempotency_key: 'evaluation:new')).to be_reserved
    expect(stale_event.reload).to be_released
  end

  it 'keeps stale reservations while their linked Voice test call is active' do
    inbox = create(:channel_api, account: account).inbox
    call = Call.create!(
      account: account,
      inbox: inbox,
      provider: :livekit,
      direction: :incoming,
      status: 'in_progress',
      provider_call_id: 'voice-test-active-reservation',
      meta: { test_call: true }
    )
    stale_limiter = described_class.new(account: account, operation: 'voice_test', now: now - 2.hours)
    stale_event = travel_to(now - 2.hours) do
      stale_limiter.reserve_or_raise!(idempotency_key: 'voice-test:active').tap { |event| event.update!(call: call) }
    end
    2.times { |index| limiter.reserve_or_raise!(idempotency_key: "evaluation:current:#{index}") }

    expect do
      limiter.reserve_or_raise!(idempotency_key: 'evaluation:blocked-by-active-call')
    end.to raise_error(AiImprovements::Usage::Exhausted)
    expect(stale_event.reload).to be_reserved
  end

  it 'keeps metering unlimited accounts without blocking work' do
    account.ai_improvement_settings = { monthly_credit_limit: 0 }
    account.save!

    2.times { |index| limiter.reserve_or_raise!(idempotency_key: "evaluation:unlimited:#{index}") }

    summary = AiImprovements::Usage::Summary.new(account: account, now: now).payload
    expect(summary).to include(unlimited: true, status: 'unlimited', remaining_credits: nil, reserved_credits: 2)
  end
end
