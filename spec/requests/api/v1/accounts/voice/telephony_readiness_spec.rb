require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Voice::TelephonyReadiness', type: :request do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/:account_id/voice/telephony_readiness' do
    it 'reports that no production phone connection exists' do
      get "/api/v1/accounts/#{account.id}/voice/telephony_readiness",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('configured' => false, 'numbers' => [])
    end

    it 'returns safe operational fields for configured numbers' do
      voice_agent = create(:voice_agent, account: account)
      inbox = create(:channel_api, account: account).inbox
      setting = create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      provider = create(
        :voice_provider_connection,
        account: account,
        provider: 'test_sip',
        status: 'active',
        settings: { 'api_token' => 'secret' }
      )
      number = create(
        :voice_number,
        account: account,
        voice_inbox_setting: setting,
        voice_provider_connection: provider,
        status: 'active'
      )

      get "/api/v1/accounts/#{account.id}/voice/telephony_readiness",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['configured']).to be(true)
      expect(response.parsed_body['numbers']).to contain_exactly(
        {
          'id' => number.id,
          'phone_number' => number.phone_number,
          'status' => 'active',
          'inbox_id' => inbox.id,
          'voice_agent_id' => voice_agent.id,
          'provider' => 'test_sip',
          'provider_status' => 'active'
        }
      )
      expect(response.body).not_to include('api_token', 'secret')
    end
  end
end
