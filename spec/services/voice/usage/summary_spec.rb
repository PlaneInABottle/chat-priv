require 'rails_helper'

RSpec.describe Voice::Usage::Summary do
  let(:account) do
    create(:account, settings: {
             voice_ai_enabled: true,
             voice_ai_monthly_minute_limit: 5,
             voice_ai_max_call_duration_minutes: 15,
             voice_ai_concurrent_call_limit: 2
           })
  end

  it 'counts rounded-up minutes for completed real LiveKit calls in the current month' do
    create_call(duration_seconds: 1)
    create_call(duration_seconds: 60)
    create_call(duration_seconds: 61)
    create_call(duration_seconds: 120, meta: { 'test_call' => true })
    create_call(duration_seconds: 120, started_at: 2.months.ago)
    create_call(duration_seconds: nil, status: 'in_progress')

    payload = described_class.new(account: account).payload

    expect(payload).to include(
      used_minutes: 4,
      remaining_minutes: 1,
      unlimited: false,
      status: 'warning',
      active_calls: 1,
      max_call_duration_minutes: 15,
      concurrent_call_limit: 2
    )
    expect(payload.dig(:metrics, :real_calls)).to eq(3)
    expect(payload.dig(:metrics, :test_calls)).to eq(1)
  end

  it 'reports disabled and unlimited states' do
    account.update!(voice_ai_enabled: false, voice_ai_monthly_minute_limit: 0)

    payload = described_class.new(account: account).payload

    expect(payload).to include(
      enabled: false,
      unlimited: true,
      remaining_minutes: nil,
      status: 'disabled'
    )
  end

  def create_call(duration_seconds:, status: 'completed', started_at: Time.current, meta: {})
    create(:call,
           account: account,
           provider: :livekit,
           status: status,
           started_at: started_at,
           duration_seconds: duration_seconds,
           meta: meta)
  end
end
