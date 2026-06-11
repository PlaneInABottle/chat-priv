require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Voice::Agents', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/:account_id/voice/agents' do
    it 'returns voice agents for the account without creating records' do
      account.voice_agents.destroy_all

      get "/api/v1/accounts/#{account.id}/voice/agents",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq([])
      expect(account.voice_agents.count).to eq(0)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/voice/agents/:id' do
    it 'returns only account-owned voice agents' do
      voice_agent = account.voice_agents.first!
      other_agent = create(:voice_agent)

      get "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['id']).to eq(voice_agent.id)

      get "/api/v1/accounts/#{account.id}/voice/agents/#{other_agent.id}",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/voice/agents' do
    it 'creates a voice agent with normalized tools config' do
      post "/api/v1/accounts/#{account.id}/voice/agents",
           params: {
             name: 'Phone support',
             enabled: true,
             prompt: 'Only speak Turkish.',
             tools_config: {
               enabled: %w[human_handoff ikas_catalog_search]
             }
           },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body).to include(
        'name' => 'Phone support',
        'enabled' => true,
        'prompt' => 'Only speak Turkish.'
      )
      expect(response.parsed_body.dig('tools_config', 'enabled')).to eq(%w[human_handoff ikas_catalog_search])
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/voice/agents/:id' do
    it 'updates only account-owned voice agents' do
      voice_agent = create(:voice_agent, account: account)
      other_agent = create(:voice_agent)

      patch "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
            params: { name: 'Updated voice' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['name']).to eq('Updated voice')

      patch "/api/v1/accounts/#{account.id}/voice/agents/#{other_agent.id}",
            params: { name: 'Invalid' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'does not allow account admins to update runtime settings' do
      voice_agent = create(:voice_agent, account: account, architecture: 'realtime', provider: 'gemini', model: nil, voice: 'Charon', language: 'tr')

      patch "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
            params: {
              name: 'Runtime attempt',
              architecture: 'pipeline',
              provider: 'openai',
              model: 'gpt-4o-realtime-preview',
              voice: 'alloy',
              language: 'en'
            },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(voice_agent.reload).to have_attributes(
        name: 'Runtime attempt',
        architecture: 'realtime',
        provider: 'gemini',
        model: nil,
        voice: 'Charon',
        language: 'tr'
      )
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/voice/agents/:id' do
    it 'destroys only account-owned voice agents' do
      voice_agent = create(:voice_agent, account: account)
      other_agent = create(:voice_agent)

      delete "/api/v1/accounts/#{account.id}/voice/agents/#{other_agent.id}",
             headers: admin.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:not_found)
      expect(other_agent.reload).to be_present

      delete "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
             headers: admin.create_new_auth_token,
             as: :json

      expect(response).to have_http_status(:no_content)
      expect { voice_agent.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
