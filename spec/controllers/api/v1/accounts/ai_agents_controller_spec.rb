require 'rails_helper'

RSpec.describe 'Ai Agent API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/ai_agent' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/ai_agent"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'creates and returns a new ai_agent if none exists' do
        expect { get "/api/v1/accounts/#{account.id}/ai_agent", headers: admin.create_new_auth_token, as: :json }
          .to change(AiAgent, :count).by(1)

        expect(response).to have_http_status(:success)

        json = response.parsed_body
        expect(json['account_id']).to eq(account.id)
        expect(json['enabled']).to be(false)
        expect(json['prompt']).to eq('')
      end

      it 'returns existing ai_agent' do
        ai_agent = create(:ai_agent, account: account)

        get "/api/v1/accounts/#{account.id}/ai_agent", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['id']).to eq(ai_agent.id)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns forbidden' do
        get "/api/v1/accounts/#{account.id}/ai_agent", headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/ai_agent' do
    let!(:ai_agent) { create(:ai_agent, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/ai_agent", params: { prompt: 'new prompt' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'updates the prompt' do
        patch "/api/v1/accounts/#{account.id}/ai_agent",
              headers: admin.create_new_auth_token,
              params: { prompt: 'You are a helpful assistant.' },
              as: :json

        expect(response).to have_http_status(:success)
        expect(ai_agent.reload.prompt).to eq('You are a helpful assistant.')
      end

      it 'updates the config' do
        patch "/api/v1/accounts/#{account.id}/ai_agent",
              headers: admin.create_new_auth_token,
              params: { config: { temperature: 0.7 } },
              as: :json

        expect(response).to have_http_status(:success)
        expect(ai_agent.reload.config).to include('temperature' => 0.7)
      end

      it 'updates enabled to true when inbox is bound' do
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/ai_agent",
              headers: admin.create_new_auth_token,
              params: { enabled: true },
              as: :json

        expect(response).to have_http_status(:success)
        expect(ai_agent.reload.enabled).to be(true)
      end

      it 'rejects enabling without bound inboxes' do
        patch "/api/v1/accounts/#{account.id}/ai_agent",
              headers: admin.create_new_auth_token,
              params: { enabled: true },
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'enables with inbox_ids in same request' do
        inbox = create(:inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/ai_agent",
              headers: admin.create_new_auth_token,
              params: { enabled: true, inbox_ids: [inbox.id] },
              as: :json

        expect(response).to have_http_status(:success)
        expect(ai_agent.reload.enabled).to be(true)
      end

      it 'syncs inbox bindings' do
        inbox = create(:inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/ai_agent",
              headers: admin.create_new_auth_token,
              params: { inbox_ids: [inbox.id] },
              as: :json

        expect(response).to have_http_status(:success)
        expect(ai_agent.agent_bot.inboxes).to include(inbox)
      end

      it 'removes inbox bindings when inbox_ids is empty' do
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/ai_agent",
              headers: admin.create_new_auth_token,
              params: { inbox_ids: [] },
              as: :json

        expect(response).to have_http_status(:success)
        expect(ai_agent.agent_bot.inboxes).to be_empty
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns forbidden' do
        patch "/api/v1/accounts/#{account.id}/ai_agent",
              headers: agent.create_new_auth_token,
              params: { prompt: 'new prompt' },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
