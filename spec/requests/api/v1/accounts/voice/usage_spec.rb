require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Voice::Usage', type: :request do
  let(:account) do
    create(:account, settings: {
             voice_ai_enabled: true,
             voice_ai_monthly_minute_limit: 10,
             voice_ai_max_call_duration_minutes: 15,
             voice_ai_concurrent_call_limit: 2
           })
  end
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/:account_id/voice/usage' do
    it 'returns voice usage summary for an authenticated administrator' do
      create(:call, account: account, provider: :livekit, status: 'completed', started_at: Time.current, duration_seconds: 61)
      create(:call, account: account, provider: :livekit, status: 'completed', started_at: Time.current, duration_seconds: 120,
                    meta: { 'test_call' => true })

      get "/api/v1/accounts/#{account.id}/voice/usage", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include(
        'period' => 'monthly',
        'enabled' => true,
        'limit_minutes' => 10,
        'used_minutes' => 2,
        'remaining_minutes' => 8,
        'unlimited' => false,
        'max_call_duration_minutes' => 15,
        'concurrent_call_limit' => 2
      )
      expect(response.parsed_body.dig('metrics', 'test_calls')).to eq(1)
    end

    it 'rejects an authenticated agent' do
      get "/api/v1/accounts/#{account.id}/voice/usage", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects users from another account' do
      other_account = create(:account, settings: { voice_ai_enabled: true })

      get "/api/v1/accounts/#{other_account.id}/voice/usage", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns disabled summary instead of forbidden when account access is off' do
      account.update!(voice_ai_enabled: false)

      get "/api/v1/accounts/#{account.id}/voice/usage", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('enabled' => false, 'status' => 'disabled')
    end
  end
end
