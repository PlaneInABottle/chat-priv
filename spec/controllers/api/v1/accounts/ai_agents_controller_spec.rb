require 'rails_helper'

RSpec.describe 'Ai Agents API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }

  def available_inboxes_by_name
    response.parsed_body['available_inboxes'].index_by { |item| item['name'] }
  end

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

      it 'returns agents sorted by created_at ascending' do
        older_agent = create(:ai_agent, account: account, created_at: 2.days.ago)
        newer_agent = create(:ai_agent, account: account, created_at: 1.hour.ago)

        get "/api/v1/accounts/#{account.id}/ai_agents", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json.length).to eq(2)
        expect(json.first['id']).to eq(older_agent.id)
        expect(json.last['id']).to eq(newer_agent.id)
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
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: account)

        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['id']).to eq(ai_agent.id)
        expect(json['name']).to eq(ai_agent.name)
        expect(json['model']).to eq('deepseek/deepseek-v4-flash')
        expect(json['conversation_limit']).to eq(0)
        expect(json['agent_bot']).to be_present
        expect(json['agent_bot']['bot_type']).to eq('ai')
        expect(json['agent_bot']['inbox_ids']).to include(inbox.id)
      end

      it 'returns available inbox ownership metadata for the detail page' do
        current_inbox = create(:inbox, account: account, name: 'Current Inbox')
        available_inbox = create(:inbox, account: account, name: 'Available Inbox')
        other_ai_agent = create(:ai_agent, account: account, name: 'Other AI Agent')
        other_ai_inbox = create(:inbox, account: account, name: 'Other AI Inbox')
        webhook_bot = create(:agent_bot, account: account, name: 'Webhook Bot')
        webhook_inbox = create(:inbox, account: account, name: 'Webhook Inbox')

        AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: current_inbox, account: account)
        AgentBotInbox.create!(agent_bot: other_ai_agent.agent_bot, inbox: other_ai_inbox, account: account)
        AgentBotInbox.create!(agent_bot: webhook_bot, inbox: webhook_inbox, account: account)

        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}", headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)

        inboxes_by_name = available_inboxes_by_name

        expect(inboxes_by_name['Available Inbox']).to include(
          'available' => true,
          'owned_by_current_ai_agent' => false,
          'conflicting' => false,
          'owner_name' => nil
        )
        expect(inboxes_by_name['Current Inbox']).to include(
          'available' => false,
          'owned_by_current_ai_agent' => true,
          'conflicting' => false,
          'owner_name' => ai_agent.name
        )
        expect(inboxes_by_name['Other AI Inbox']).to include(
          'available' => false,
          'owned_by_current_ai_agent' => false,
          'conflicting' => true,
          'owner_name' => 'Other AI Agent'
        )
        expect(inboxes_by_name['Webhook Inbox']).to include(
          'available' => false,
          'owned_by_current_ai_agent' => false,
          'conflicting' => true,
          'owner_name' => 'Webhook Bot'
        )
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

      it 'returns available inbox ownership metadata in create response' do
        assigned_inbox = create(:inbox, account: account, name: 'Assigned Inbox')
        conflicting_agent = create(:ai_agent, account: account, name: 'Busy Agent')
        conflicting_inbox = create(:inbox, account: account, name: 'Conflicting Inbox')

        AgentBotInbox.create!(agent_bot: conflicting_agent.agent_bot, inbox: conflicting_inbox, account: account)

        post "/api/v1/accounts/#{account.id}/ai_agents",
             headers: admin.create_new_auth_token,
             params: { name: 'New Agent', inbox_ids: [assigned_inbox.id] },
             as: :json

        expect(response).to have_http_status(:success)

        inboxes_by_name = available_inboxes_by_name
        expect(inboxes_by_name['Assigned Inbox']).to include(
          'available' => false,
          'owned_by_current_ai_agent' => true,
          'conflicting' => false,
          'owner_name' => 'New Agent'
        )
        expect(inboxes_by_name['Conflicting Inbox']).to include(
          'available' => false,
          'owned_by_current_ai_agent' => false,
          'conflicting' => true,
          'owner_name' => 'Busy Agent'
        )
      end

      it 'returns 422 with invalid params' do
        post "/api/v1/accounts/#{account.id}/ai_agents",
             headers: admin.create_new_auth_token,
             params: { name: '' },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'returns 422 when assigning inbox already bound to another AI agent' do
        other_agent = create(:ai_agent, account: account)
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: other_agent.agent_bot, inbox: inbox, account: account)

        post "/api/v1/accounts/#{account.id}/ai_agents",
             headers: admin.create_new_auth_token,
             params: { name: 'New Agent', inbox_ids: [inbox.id] },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['errors']).to have_key('inbox_ids')
      end

      it 'returns 422 when assigning inbox already bound to a webhook bot' do
        webhook_bot = create(:agent_bot, account: account)
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: webhook_bot, inbox: inbox, account: account)

        post "/api/v1/accounts/#{account.id}/ai_agents",
             headers: admin.create_new_auth_token,
             params: { name: 'New Agent', inbox_ids: [inbox.id] },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['errors']).to have_key('inbox_ids')
        expect(inbox.reload.agent_bot.id).to eq(webhook_bot.id)
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

      it 'returns empty inbox_ids in the response after removing bindings' do
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
              headers: admin.create_new_auth_token,
              params: { inbox_ids: [] },
              as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body.dig('agent_bot', 'inbox_ids')).to eq([])
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

      it 'returns 422 when assigning inbox already bound to a webhook bot' do
        webhook_bot = create(:agent_bot, account: account)
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: webhook_bot, inbox: inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
              headers: admin.create_new_auth_token,
              params: { inbox_ids: [inbox.id] },
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['errors']).to have_key('inbox_ids')
        expect(inbox.reload.agent_bot.id).to eq(webhook_bot.id)
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

      it 'returns available inbox ownership metadata in update response' do
        assigned_inbox = create(:inbox, account: account, name: 'Assigned Inbox')
        conflicting_agent = create(:ai_agent, account: account, name: 'Busy Agent')
        conflicting_inbox = create(:inbox, account: account, name: 'Conflicting Inbox')

        AgentBotInbox.create!(agent_bot: conflicting_agent.agent_bot, inbox: conflicting_inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
              headers: admin.create_new_auth_token,
              params: { name: 'Updated Name', inbox_ids: [assigned_inbox.id] },
              as: :json

        expect(response).to have_http_status(:success)

        inboxes_by_name = available_inboxes_by_name
        expect(inboxes_by_name['Assigned Inbox']).to include(
          'available' => false,
          'owned_by_current_ai_agent' => true,
          'conflicting' => false,
          'owner_name' => 'Updated Name'
        )
        expect(inboxes_by_name['Conflicting Inbox']).to include(
          'available' => false,
          'owned_by_current_ai_agent' => false,
          'conflicting' => true,
          'owner_name' => 'Busy Agent'
        )
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

      it 'removes inbox bindings immediately on delete' do
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: account)

        expect do
          delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}",
                 headers: admin.create_new_auth_token,
                 as: :json
        end.to change(AgentBotInbox, :count).by(-1)

        expect(response).to have_http_status(:no_content)
        expect(AgentBotInbox.where(inbox_id: inbox.id)).to be_empty
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
