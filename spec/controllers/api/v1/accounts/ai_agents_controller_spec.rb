require 'rails_helper'

RSpec.describe 'Ai Agents API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }

  describe 'GET /api/v1/accounts/{account.id}/ai_agents' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/ai_agents"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'returns empty array when no agents exist' do
        get "/api/v1/accounts/#{account.id}/ai_agents", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to eq([])
      end

      it 'returns array of ai agents' do
        ai_agent = create(:ai_agent, account: account)

        get "/api/v1/accounts/#{account.id}/ai_agents", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json.length).to eq(1)
        expect(json.first['id']).to eq(ai_agent.id)
        expect(json.first['name']).to eq(ai_agent.name)
        expect(json.first['conversation_limit']).to eq(0)
        expect(json.first['ai_agent_model']).to eq('deepseek/deepseek-v4-flash')
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns forbidden' do
        get "/api/v1/accounts/#{account.id}/ai_agents", headers: agent_user.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/ai_agents/:id' do
    let!(:ai_agent) { create(:ai_agent, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'returns the ai agent with nested bot and inboxes' do
        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['id']).to eq(ai_agent.id)
        expect(json['name']).to eq(ai_agent.name)
        expect(json['model']).to eq('deepseek/deepseek-v4-flash')
        expect(json['conversation_limit']).to eq(0)
        expect(json['agent_bot']).to be_present
        expect(json['agent_bot']['bot_type']).to eq('ai')
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns forbidden' do
        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", headers: agent_user.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/ai_agents' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/ai_agents", params: { name: 'New Agent' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'creates an ai agent with linked bot' do
        expect do
          post "/api/v1/accounts/#{account.id}/ai_agents",
               headers: admin.create_new_auth_token,
               params: { name: 'New Agent', prompt: 'Helpful assistant' },
               as: :json
        end.to change(AiAgent, :count).by(1).and change(AgentBot, :count).by(1)

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['name']).to eq('New Agent')
        expect(json['prompt']).to eq('Helpful assistant')
        expect(json['agent_bot']).to be_present
        expect(json['agent_bot']['name']).to eq('New Agent')
        expect(json['agent_bot']['bot_type']).to eq('ai')
      end

      it 'creates agent and syncs inbox bindings' do
        inbox = create(:inbox, account: account)

        post "/api/v1/accounts/#{account.id}/ai_agents",
             headers: admin.create_new_auth_token,
             params: { name: 'New Agent', inbox_ids: [inbox.id] },
             as: :json

        expect(response).to have_http_status(:success)
        agent_bot = AgentBot.last
        expect(agent_bot.inboxes).to include(inbox)
      end

      it 'returns 422 with invalid params' do
        post "/api/v1/accounts/#{account.id}/ai_agents",
             headers: admin.create_new_auth_token,
             params: { name: '' },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns forbidden' do
        post "/api/v1/accounts/#{account.id}/ai_agents",
             headers: agent_user.create_new_auth_token,
             params: { name: 'New Agent' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/{account.id}/ai_agents/:id' do
    let!(:ai_agent) { create(:ai_agent, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", params: { prompt: 'new prompt' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'updates the prompt' do
        patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
              headers: admin.create_new_auth_token,
              params: { prompt: 'You are a helpful assistant.' },
              as: :json

        expect(response).to have_http_status(:success)
        expect(ai_agent.reload.prompt).to eq('You are a helpful assistant.')
      end

      it 'syncs inbox bindings' do
        inbox = create(:inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
              headers: admin.create_new_auth_token,
              params: { inbox_ids: [inbox.id] },
              as: :json

        expect(response).to have_http_status(:success)
        expect(ai_agent.agent_bot.inboxes).to include(inbox)
      end

      it 'removes inbox bindings when inbox_ids is empty' do
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
              headers: admin.create_new_auth_token,
              params: { inbox_ids: [] },
              as: :json

        expect(response).to have_http_status(:success)
        expect(ai_agent.agent_bot.inboxes.reload).to be_empty
      end

      it 'returns 422 when assigning inbox already bound to another AI agent' do
        other_agent = create(:ai_agent, account: account)
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: other_agent.agent_bot, inbox: inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
              headers: admin.create_new_auth_token,
              params: { inbox_ids: [inbox.id] },
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['errors']).to have_key('inbox_ids')
      end

      it 'updates agent_bot name to match ai_agent name' do
        patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
              headers: admin.create_new_auth_token,
              params: { name: 'Updated Name' },
              as: :json

        expect(response).to have_http_status(:success)
        expect(ai_agent.reload.name).to eq('Updated Name')
        expect(ai_agent.agent_bot.reload.name).to eq('Updated Name')
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns forbidden' do
        patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
              headers: agent_user.create_new_auth_token,
              params: { prompt: 'new prompt' },
              as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/ai_agents/:id' do
    let!(:ai_agent) { create(:ai_agent, account: account) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'removes agent, bot, and test conversations' do
        test_conversation = create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent)
        bot = ai_agent.agent_bot

        expect do
          delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
                 headers: admin.create_new_auth_token,
                 as: :json
        end.to change(AiAgent, :count).by(-1)
          .and change(AgentBot, :count).by(-1)
          .and change(AiAgentTestConversation, :count).by(-1)

        expect(response).to have_http_status(:no_content)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns forbidden' do
        delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
               headers: agent_user.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
