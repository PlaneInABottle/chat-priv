require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Voice::Agents', type: :request do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:instructions) do
    {
      version: 4,
      locale: 'en',
      profile: { language: 'en', tone: 'professional', formality: 'formal', response_length: 'short' },
      sections: { business_context: 'Retail', tasks: 'Answer questions.', rules: 'Never invent prices.' }
    }
  end

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
      expect(response.parsed_body['instructions']).to be_nil
    end

    it 'creates structured instructions, compiles the prompt, and hides reserved config' do
      post "/api/v1/accounts/#{account.id}/voice/agents",
           params: {
             name: 'Structured voice',
             instructions: instructions,
             config: { injected: true }
           },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:created)
      expect(response.parsed_body['instructions']).to eq(instructions.deep_stringify_keys)
      expect(response.parsed_body['config']).to eq({})
      stored = VoiceAgent.find(response.parsed_body['id'])
      expect(stored.config).to eq('instructions' => instructions.deep_stringify_keys)
      expect(stored.prompt).to eq(VoiceAgents::InstructionDocument.new(instructions).compile)
    end

    it 'rejects malformed instructions without creating a record' do
      post "/api/v1/accounts/#{account.id}/voice/agents",
           params: { name: 'Invalid instructions', instructions: nil },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('attributes' => ['instructions'])
      expect(account.voice_agents).to be_empty
    end

    it 'rejects prompt and instructions together without creating a record' do
      post "/api/v1/accounts/#{account.id}/voice/agents",
           params: { name: 'Conflicting', prompt: 'Legacy', instructions: instructions },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('attributes' => ['instructions'])
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

    it 'preserves structured instructions on omission and replaces them atomically' do
      voice_agent = create(
        :voice_agent,
        account: account,
        config: {
          'runtime_sibling' => 'keep',
          'authoring_profile' => { 'tone' => 'friendly' },
          'instructions' => instructions.deep_stringify_keys
        },
        prompt: VoiceAgents::InstructionDocument.new(instructions).compile
      )
      path = "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}"
      headers = admin.create_new_auth_token

      patch path, params: { name: 'Omitted instructions' }, headers: headers, as: :json
      expect(response.parsed_body['instructions']).to eq(instructions.deep_stringify_keys)
      expect(response.parsed_body['prompt']).to eq(VoiceAgents::InstructionDocument.new(instructions).compile)

      replacement = instructions.deep_merge(sections: { rules: 'Updated rule.' })
      patch path,
            params: { instructions: replacement, config: { runtime_sibling: 'replace', injected: true } },
            headers: headers,
            as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['config']).to eq('runtime_sibling' => 'keep')
      expect(voice_agent.reload.config).to eq(
        'runtime_sibling' => 'keep', 'instructions' => replacement.deep_stringify_keys
      )
      expect(voice_agent.instructions.dig('sections', 'rules')).to eq('Updated rule.')
    end

    it 'accepts prompt-only updates for legacy records and preserves unrelated config' do
      voice_agent = create(:voice_agent, account: account, prompt: 'Old prompt', config: { 'runtime' => true })

      patch "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
            params: { prompt: 'Updated legacy prompt' },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      expect(voice_agent.reload).to have_attributes(prompt: 'Updated legacy prompt', config: { 'runtime' => true })
      expect(response.parsed_body['instructions']).to be_nil
    end

    it 'atomically rejects instruction conflicts and malformed values before related writes' do
      voice_agent = create(
        :voice_agent,
        account: account,
        config: { 'runtime' => true, 'instructions' => instructions.deep_stringify_keys },
        prompt: VoiceAgents::InstructionDocument.new(instructions).compile,
        last_tested_at: Time.current,
        last_tested_draft_fingerprint: 'preserve'
      )
      inbox = create(:channel_api, account: account).inbox
      source = create(:ai_knowledge_source, account: account)
      path = "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}"
      invalid_requests = [
        { prompt: 'legacy replacement' },
        { prompt: 'both', instructions: instructions },
        nil,
        [],
        'invalid',
        instructions.deep_merge(extra: true),
        instructions.deep_merge(version: 3),
        instructions.deep_merge(locale: 'de'),
        instructions.deep_merge(profile: { tone: 'unsupported' }),
        instructions.deep_merge(sections: { rules: 3 }),
        instructions.deep_merge(sections: { rules: 'x' * 50_001 })
      ]

      invalid_requests.each do |invalid|
        original_attributes = voice_agent.reload.attributes
        request_params = if invalid.is_a?(Hash) && (invalid.key?(:prompt) || invalid.key?(:instructions))
                           invalid.merge(name: 'Must not persist')
                         else
                           {
                             name: 'Must not persist',
                             instructions: invalid,
                             inbox_settings: [{ inbox_id: inbox.id }],
                             knowledge_source_ids: [source.id]
                           }
                         end
        patch path,
              params: request_params,
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body).to include('attributes' => ['instructions'])
        expect(voice_agent.reload.attributes).to eq(original_attributes)
        expect(voice_agent.voice_inbox_settings).to be_empty
        expect(voice_agent.knowledge_source_ids).to be_empty
      end
    end

    it 'returns null instructions for legacy or malformed stored records and hides reserved config' do
      voice_agent = create(
        :voice_agent,
        account: account,
        config: {
          'runtime' => true,
          'authoring_profile' => { 'tone' => 'invalid' },
          'instructions' => { 'version' => 3 }
        }
      )

      get "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response.parsed_body['instructions']).to be_nil
      expect(response.parsed_body).not_to have_key('authoring_profile')
      expect(response.parsed_body['config']).to eq('runtime' => true)
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
