require 'rails_helper'

RSpec.describe Voice::Usage::Admission do
  let(:account) do
    create(:account, settings: {
             voice_ai_enabled: true,
             voice_ai_monthly_minute_limit: 2,
             voice_ai_concurrent_call_limit: 1
           })
  end

  it 'allows calls when account access and limits allow it' do
    result = described_class.new(account: account).call

    expect(result).to be_allowed
  end

  it 'blocks disabled accounts' do
    account.update!(voice_ai_enabled: false)

    result = described_class.new(account: account).call

    expect(result.status).to eq(:voice_ai_disabled)
    expect { described_class.check!(account: account) }.to raise_error do |error|
      expect(error.class.name).to eq('Voice::Usage::Admission::Error')
      expect(error.message).to eq('Voice AI is disabled for this account.')
    end
  end

  it 'blocks exhausted monthly limits for real calls' do
    create_call(duration_seconds: 61)

    result = described_class.new(account: account).call

    expect(result.status).to eq(:monthly_limit_exhausted)
  end

  it 'blocks real calls when the concurrent call limit is reached' do
    create_call(status: 'in_progress', duration_seconds: nil)

    result = described_class.new(account: account).call

    expect(result.status).to eq(:concurrent_limit_reached)
  end

  it 'excludes sandbox calls from monthly and concurrent limits' do
    create_call(duration_seconds: 61)
    create_call(status: 'in_progress', duration_seconds: nil)

    result = described_class.new(account: account, test_call: true).call

    expect(result).to be_allowed
  end

  it 'allows unlimited monthly and concurrent limits when set to zero' do
    account.update!(voice_ai_monthly_minute_limit: 0, voice_ai_concurrent_call_limit: 0)
    create_call(duration_seconds: 3600)
    create_call(status: 'in_progress', duration_seconds: nil)

    result = described_class.new(account: account).call

    expect(result).to be_allowed
  end

  def create_call(duration_seconds:, status: 'completed', meta: {})
    create(:call,
           account: account,
           provider: :livekit,
           status: status,
           started_at: Time.current,
           duration_seconds: duration_seconds,
           meta: meta)
  end
end
