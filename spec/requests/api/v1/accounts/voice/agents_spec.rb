require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Voice::Agents', type: :request do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/:account_id/voice/agents' do
    it 'returns voice agents for the account without creating records' do
      get "/api/v1/accounts/#{account.id}/voice/agents",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']).to eq([])
      expect(account.voice_agents.count).to eq(0)
    end

    it 'rejects requests when account Voice AI access is disabled' do
      account.update!(voice_ai_enabled: false)

      get "/api/v1/accounts/#{account.id}/voice/agents",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('Voice AI is disabled for this account.')
    end
  end

  describe 'GET /api/v1/accounts/:account_id/voice/agents/:id' do
    it 'returns only account-owned voice agents' do
      voice_agent = create(:voice_agent, account: account)
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

    it 'creates a voice agent and strips unavailable integration tools' do
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
        'enabled' => false,
        'prompt' => 'Only speak Turkish.'
      )
      expect(response.parsed_body.dig('tools_config', 'enabled')).to eq(%w[human_handoff end_customer_call])
      expect(response.parsed_body['authoring_profile']).to eq(VoiceAgents::AuthoringProfile::DEFAULTS)
    end

    it 'creates and returns a normalized authoring profile without exposing it in config' do
      post "/api/v1/accounts/#{account.id}/voice/agents",
           params: {
             name: 'Profiled voice',
             authoring_profile: { tone: 'professional', business_context: 'Retail', boundaries: 'No refunds' },
             config: { injected: true }
           },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['authoring_profile']).to eq(
        'tone' => 'professional', 'business_context' => 'Retail', 'boundaries' => 'No refunds'
      )
      expect(response.parsed_body['config']).to eq({})
      expect(VoiceAgent.find(response.parsed_body['id']).config).to eq(
        'authoring_profile' => response.parsed_body['authoring_profile']
      )
    end

    it 'rejects malformed authoring profiles without creating a record' do
      post "/api/v1/accounts/#{account.id}/voice/agents",
           params: { name: 'Invalid profile', authoring_profile: nil },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('attributes' => ['authoring_profile'])
      expect(account.voice_agents).to be_empty
    end

    it 'uses deployment-controlled OpenAI runtime defaults without accepting runtime params from account admins' do
      with_modified_env VOICE_AGENT_DEFAULT_REALTIME_PROVIDER: 'openai' do
        post "/api/v1/accounts/#{account.id}/voice/agents",
             params: {
               name: 'OpenAI default',
               provider: 'gemini',
               model: 'gemini-3.1-flash-live-preview',
               voice: 'Charon'
             },
             headers: admin.create_new_auth_token,
             as: :json
      end

      expect(response).to have_http_status(:created)
      expect(VoiceAgent.find(response.parsed_body['id'])).to have_attributes(
        provider: 'openai',
        model: 'gpt-realtime-2.1',
        voice: 'marin'
      )
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
      voice_agent = create(:voice_agent, account: account, enabled: false)
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
      voice_agent = create(
        :voice_agent,
        account: account,
        enabled: false,
        architecture: 'realtime',
        provider: 'gemini',
        model: nil,
        voice: 'Charon',
        language: 'tr'
      )

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

    it 'partially merges, preserves on omission, clears text, and ignores arbitrary config' do
      voice_agent = create(
        :voice_agent,
        account: account,
        config: {
          'runtime_sibling' => 'keep',
          'authoring_profile' => { 'tone' => 'friendly', 'business_context' => 'Keep context', 'boundaries' => 'Keep boundary' }
        }
      )
      path = "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}"
      headers = admin.create_new_auth_token

      patch path, params: { name: 'Omitted profile' }, headers: headers, as: :json
      expect(response.parsed_body['authoring_profile']).to include('business_context' => 'Keep context')

      patch path,
            params: { authoring_profile: { tone: 'concise' }, config: { runtime_sibling: 'replace', injected: true } },
            headers: headers,
            as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['authoring_profile']).to eq(
        'tone' => 'concise', 'business_context' => 'Keep context', 'boundaries' => 'Keep boundary'
      )
      expect(response.parsed_body['config']).to eq('runtime_sibling' => 'keep')

      patch path,
            params: { authoring_profile: { business_context: '', boundaries: '' } },
            headers: headers,
            as: :json
      expect(response.parsed_body['authoring_profile']).to eq(
        'tone' => 'concise', 'business_context' => '', 'boundaries' => ''
      )
      expect(voice_agent.reload.config).to include('runtime_sibling' => 'keep')
      expect(voice_agent.config).not_to have_key('injected')
    end

    it 'atomically rejects invalid authoring profile shapes and fields' do
      voice_agent = create(
        :voice_agent,
        account: account,
        config: { 'runtime' => true, 'authoring_profile' => { 'tone' => 'friendly' } }
      )
      path = "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}"
      invalid_profiles = [
        nil,
        [],
        'invalid',
        { tone: 'unsupported' },
        { business_context: 3 },
        { boundaries: 'x' * 2001 }
      ]

      invalid_profiles.each do |profile|
        original_attributes = voice_agent.reload.attributes
        patch path,
              params: { name: 'Must not persist', authoring_profile: profile },
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('attributes' => ['authoring_profile'])
        expect(voice_agent.reload.attributes).to eq(original_attributes)
      end
    end

    it 'returns field-by-field defaults for legacy malformed stored profiles' do
      voice_agent = create(
        :voice_agent,
        account: account,
        config: {
          'runtime' => true,
          'authoring_profile' => { 'tone' => 'invalid', 'business_context' => 'Valid', 'boundaries' => 4 }
        }
      )

      get "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response.parsed_body['authoring_profile']).to eq(
        'tone' => 'friendly', 'business_context' => 'Valid', 'boundaries' => ''
      )
      expect(response.parsed_body['config']).to eq('runtime' => true)
    end

    it 'preserves release identity, successful test state, and readiness for profile-only updates' do
      voice_agent = create(:voice_agent, account: account, enabled: false)
      inbox = create(:channel_api, account: account).inbox
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      voice_agent.mark_test_succeeded!
      voice_agent.publish!(activate: false)
      fingerprint = voice_agent.draft_fingerprint
      tested_at = voice_agent.last_tested_at
      readiness = voice_agent.readiness
      revision = voice_agent.published_revision

      patch "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
            params: { authoring_profile: { tone: 'professional' } },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(voice_agent.reload).to have_attributes(
        draft_fingerprint: fingerprint,
        last_tested_at: tested_at,
        last_tested_draft_fingerprint: fingerprint,
        published_revision: revision
      )
      expect(voice_agent).to be_draft_tested
      expect(voice_agent).not_to be_draft_changes
      expect(voice_agent.readiness).to eq(readiness)
    end

    it 'moves an inbox assignment from another voice agent to the updated voice agent' do
      inbox = create(:channel_api, account: account).inbox
      original_agent = create(:voice_agent, account: account, name: 'Original')
      target_agent = create(:voice_agent, account: account, name: 'Target', enabled: false)
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

  describe 'voice assistant lifecycle actions' do
    let(:voice_agent) { create(:voice_agent, account: account, enabled: false) }

    it 'publishes a ready draft and pauses it explicitly' do
      inbox = create(:channel_api, account: account).inbox
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      voice_agent.mark_test_succeeded!

      post "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/publish",
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('lifecycle_status' => 'active', 'enabled' => true)

      post "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/pause",
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('lifecycle_status' => 'paused', 'enabled' => false)
      expect(response.parsed_body['last_tested_at']).to be_present
    end

    it 'applies edits while active without taking the assistant offline' do
      voice_agent.update!(enabled: true, published_at: Time.current)

      patch "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
            params: { name: 'Live edit' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(voice_agent.reload).to have_attributes(name: 'Live edit', enabled: true, last_tested_at: nil)
    end

    it 'publishes without starting traffic and activates the release separately' do
      inbox = create(:channel_api, account: account).inbox
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      voice_agent.mark_test_succeeded!

      post "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/publish",
           params: { activate: false },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('lifecycle_status' => 'paused', 'enabled' => false, 'published_revision' => 1)

      post "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/activate",
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('lifecycle_status' => 'active', 'enabled' => true, 'published_revision' => 1)
    end

    it 'rejects activation before the first release is published' do
      post "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/activate",
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to eq('Publish the assistant before activation.')
    end
  end
end
