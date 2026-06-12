require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Voice::Agents', type: :request do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
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
    it 'rejects creation when account Voice AI access is disabled' do
      account.update!(voice_ai_enabled: false)

      post "/api/v1/accounts/#{account.id}/voice/agents",
           params: { name: 'Blocked voice' },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('Voice AI is disabled for this account.')
    end

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

    it 'creates inbox assignments for the voice agent' do
      inbox = create(:channel_api, account: account).inbox
      team = create(:team, account: account)

      post "/api/v1/accounts/#{account.id}/voice/agents",
           params: {
             name: 'Phone support',
             enabled: true,
             inbox_settings: [
               {
                 inbox_id: inbox.id,
                 fallback_team_id: team.id,
                 recording_enabled: true
               }
             ]
           },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:created)
      assignment = response.parsed_body['inbox_settings'].first
      expect(assignment).to include(
        'inbox_id' => inbox.id,
        'fallback_team_id' => team.id,
        'recording_enabled' => true
      )
      expect(assignment).not_to have_key('status')
      expect(VoiceInboxSetting.find(assignment['id'])).to have_attributes(
        inbox_id: inbox.id,
        fallback_team_id: team.id,
        voice_agent_id: response.parsed_body['id']
      )
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

    it 'moves an inbox assignment from another voice agent to the updated voice agent' do
      inbox = create(:channel_api, account: account).inbox
      original_agent = create(:voice_agent, account: account, name: 'Original')
      target_agent = create(:voice_agent, account: account, name: 'Target')
      setting = create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: original_agent)

      patch "/api/v1/accounts/#{account.id}/voice/agents/#{target_agent.id}",
            params: {
              inbox_settings: [
                {
                  inbox_id: inbox.id,
                  recording_enabled: true
                }
              ]
            },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(setting.reload).to have_attributes(
        voice_agent_id: target_agent.id,
        recording_enabled: true
      )
      expect(response.parsed_body['inbox_settings'].pluck('id')).to eq([setting.id])
    end

    it 'removes omitted inbox assignments for the updated voice agent' do
      voice_agent = create(:voice_agent, account: account)
      kept_inbox = create(:channel_api, account: account).inbox
      removed_inbox = create(:channel_api, account: account).inbox
      kept_setting = create(:voice_inbox_setting, account: account, inbox: kept_inbox, voice_agent: voice_agent)
      removed_setting = create(:voice_inbox_setting, account: account, inbox: removed_inbox, voice_agent: voice_agent)

      patch "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
            params: {
              inbox_settings: [
                {
                  inbox_id: kept_inbox.id,
                  recording_enabled: false
                }
              ]
            },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(VoiceInboxSetting.exists?(kept_setting.id)).to be(true)
      expect(VoiceInboxSetting.exists?(removed_setting.id)).to be(false)
    end

    it 'rejects cross-account inbox assignments' do
      voice_agent = create(:voice_agent, account: account)
      other_inbox = create(:channel_api).inbox

      patch "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
            params: {
              inbox_settings: [
                {
                  inbox_id: other_inbox.id,
                  recording_enabled: false
                }
              ]
            },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:not_found)
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
