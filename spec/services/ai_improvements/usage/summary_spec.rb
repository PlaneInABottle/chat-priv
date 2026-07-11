require 'rails_helper'

RSpec.describe AiImprovements::Usage::Summary do
  let(:now) { Time.zone.parse('2026-07-11 12:00:00 UTC') }
  let(:account) do
    create(:account, settings: { ai_improvement_monthly_credit_limit: 10, reporting_timezone: 'Etc/UTC' })
  end

  it 'returns used, reserved, remaining, and operation breakdown totals' do
    evaluation_limiter = AiImprovements::Usage::Limiter.new(account: account, operation: 'evaluation', now: now)
    evaluation_event = evaluation_limiter.reserve_or_raise!
    evaluation_limiter.consume!(evaluation_event, unit_type: 'tokens', units: 1_001)
    AiImprovements::Usage::Limiter.new(account: account, operation: 'text_test', now: now).reserve_or_raise!

    payload = described_class.new(account: account, now: now).payload

    expect(payload).to include(
      limit_credits: 10,
      used_credits: 2,
      reserved_credits: 1,
      remaining_credits: 7,
      status: 'ok',
      breakdown: { 'evaluation' => 2 }
    )
    expect(payload[:reset_at]).to eq('2026-08-01T00:00:00Z')
  end

  it 'does not warn while a small allowance remains mostly unused' do
    account.ai_improvement_settings = { monthly_credit_limit: 1 }
    account.save!

    expect(described_class.new(account: account, now: now).payload[:status]).to eq('ok')
  end
end
