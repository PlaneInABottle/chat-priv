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

  describe 'freemium monthly credit pool' do
    let(:freemium_account) do
      create(:account, settings: {
               ai_improvement_monthly_credit_limit: Account::FREEMIUM_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT,
               reporting_timezone: 'Etc/UTC'
             })
    end
    let(:period) { AiAgents::Usage::Period.new(account: freemium_account, now: now) }

    def create_consumed_credits(account:, credits:, idempotency_key:, operation: 'text_test')
      period = AiAgents::Usage::Period.new(account: account, now: now)
      AiImprovementUsageEvent.create!(
        account: account, operation: operation, unit_type: 'tokens', units: credits * 1_000, credits: credits,
        status: :consumed, period_start_at: period.start_at, period_end_at: period.end_at,
        idempotency_key: idempotency_key
      )
    end

    it 'admits the 600th credit and rejects the 601st at the freemium limit' do
      create_consumed_credits(account: freemium_account, credits: 599, idempotency_key: 'freemium-seed-599')
      limiter = described_class.new(account: freemium_account, operation: 'text_test', now: now)

      expect { limiter.reserve_or_raise!(idempotency_key: 'freemium-600th') }.to change(AiImprovementUsageEvent.reserved, :count).by(1)

      expect do
        limiter.reserve_or_raise!(idempotency_key: 'freemium-601st')
      end.to raise_error(AiImprovements::Usage::Exhausted) { |error| expect(error.summary[:remaining_credits]).to eq(0) }

      expect(AiImprovementUsageEvent.reserved.sum(:credits)).to eq(1)
    end

    it 'shares one pool across operations so one operation reduces another allowance' do
      create_consumed_credits(account: freemium_account, credits: 300, idempotency_key: 'shared-text-300')
      create_consumed_credits(account: freemium_account, credits: 299, operation: 'website_import', idempotency_key: 'shared-import-299')
      import_limiter = described_class.new(account: freemium_account, operation: 'website_import', now: now)

      expect { import_limiter.reserve_or_raise!(idempotency_key: 'shared-600th') }.to change(AiImprovementUsageEvent.reserved, :count).by(1)

      expect do
        import_limiter.reserve_or_raise!(idempotency_key: 'shared-601st')
      end.to raise_error(AiImprovements::Usage::Exhausted) { |error| expect(error.summary[:remaining_credits]).to eq(0) }

      summary = AiImprovements::Usage::Summary.new(account: freemium_account, now: now).payload
      expect(summary[:breakdown]).to eq('text_test' => 300, 'website_import' => 299)
      expect(AiImprovementUsageEvent.reserved.sum(:credits)).to eq(1)
    end

    it 'resets the pool at the reporting-timezone month boundary' do
      july_account = create(:account, settings: {
                              ai_improvement_monthly_credit_limit: 600,
                              reporting_timezone: 'America/New_York'
                            })
      july_period = AiAgents::Usage::Period.new(account: july_account, now: Time.zone.parse('2026-07-11 12:00:00 UTC'))
      AiImprovementUsageEvent.create!(
        account: july_account, operation: 'text_test', unit_type: 'tokens', units: 600_000, credits: 600,
        status: :consumed, period_start_at: july_period.start_at, period_end_at: july_period.end_at,
        idempotency_key: 'july-600'
      )

      august_now = Time.zone.parse('2026-08-05 12:00:00 UTC')
      event = described_class.new(account: july_account, operation: 'text_test', now: august_now).reserve_or_raise!(idempotency_key: 'august-first')

      expect(event.period_start_at).to eq(Time.zone.parse('2026-08-01 04:00:00 UTC'))
      expect(event.period_end_at).to eq(Time.zone.parse('2026-09-01 04:00:00 UTC'))
      expect(AiImprovements::Usage::Summary.new(account: july_account, now: august_now).payload[:remaining_credits]).to eq(599)
    end

    it 'applies limit changes immediately without rewriting usage events' do
      create_consumed_credits(account: freemium_account, credits: 300, idempotency_key: 'immediate-300')
      limiter = described_class.new(account: freemium_account, operation: 'text_test', now: now)

      freemium_account.update!(ai_improvement_monthly_credit_limit: 100)
      expect do
        limiter.reserve_or_raise!(idempotency_key: 'immediate-lowered')
      end.to raise_error(AiImprovements::Usage::Exhausted)
      expect(AiImprovementUsageEvent.reserved.sum(:credits)).to eq(0)

      freemium_account.update!(ai_improvement_monthly_credit_limit: 500)
      expect { limiter.reserve_or_raise!(idempotency_key: 'immediate-raised') }.to change(AiImprovementUsageEvent.reserved, :count).by(1)

      summary = AiImprovements::Usage::Summary.new(account: freemium_account, now: now).payload
      expect(summary[:remaining_credits]).to eq(199)
      expect(summary[:used_credits]).to eq(300)
    end
  end

  describe 'concurrent reservations' do
    self.use_transactional_tests = false

    it 'never over-allocates when 800 reservations race for 600 credits' do
      account = create(:account, settings: {
                         ai_improvement_monthly_credit_limit: 600,
                         reporting_timezone: 'Etc/UTC'
                       })
      now = Time.zone.parse('2026-07-11 12:00:00 UTC')

      results = Concurrent::Array.new
      barrier = Concurrent::CyclicBarrier.new(4)

      threads = Array.new(4) do |thread_index|
        Thread.new do
          barrier.wait
          thread_account = Account.find(account.id)
          thread_limiter = described_class.new(account: thread_account, operation: 'text_test', now: now)
          200.times do |key_index|
            thread_limiter.reserve_or_raise!(idempotency_key: "concurrent-t#{thread_index}-k#{key_index}")
            results << :reserved
          rescue AiImprovements::Usage::Exhausted
            results << :exhausted
          end
        end
      end

      unfinished = threads.reject { |thread| thread.join(60) }
      expect(unfinished).to be_empty
      threads.each(&:value)

      expect(results.count { |status| status == :reserved }).to eq(600)
      expect(results.count { |status| status == :exhausted }).to eq(200)
      expect(AiImprovementUsageEvent.where(account: account).reserved.sum(:credits)).to eq(600)
      expect(AiImprovementUsageEvent.where(account: account).count).to eq(600)
    ensure
      if account
        AiImprovementUsageEvent.where(account_id: account.id).delete_all
        account.delete
      end
    end
  end
end
