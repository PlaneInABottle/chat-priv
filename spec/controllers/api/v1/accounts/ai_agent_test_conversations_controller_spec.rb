require 'rails_helper'

RSpec.describe 'Ai Agent Test Conversations API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:ai_agent) { create(:ai_agent, account: account) }

  describe 'GET /api/v1/accounts/{account.id}/ai_agents/{ai_agent.id}/test_conversations' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'returns an empty array when no test conversations exist' do
        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to eq([])
      end

      it 'returns test conversations ordered by recency' do
        old_conversation = create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent, last_message_at: 2.days.ago)
        new_conversation = create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent, last_message_at: 1.hour.ago)

        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json.length).to eq(2)
        expect(json.first['id']).to eq(new_conversation.id)
        expect(json.last['id']).to eq(old_conversation.id)
      end

      it 'does not return test conversations from other accounts' do
        other_account = create(:account)
        other_ai_agent = create(:ai_agent, account: other_account)
        create(:ai_agent_test_conversation, account: other_account, ai_agent: other_ai_agent)
        local_conversation = create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent)

        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json.length).to eq(1)
        expect(json.first['id']).to eq(local_conversation.id)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/ai_agents/{ai_agent.id}/test_conversations/:id' do
    let!(:test_conversation) { create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'returns the test conversation with messages' do
        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['id']).to eq(test_conversation.id)
        expect(json['title']).to eq(test_conversation.title)
        expect(json['messages']).to eq(test_conversation.messages)
        expect(json['messages_count']).to eq(0)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/ai_agents/{ai_agent.id}/test_conversations' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'creates a new empty test conversation with default title' do
        expect do
          post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations",
               headers: admin.create_new_auth_token,
               as: :json
        end.to change(AiAgentTestConversation, :count).by(1)

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        expect(json['title']).to eq('New Test Conversation')
        expect(json['messages']).to eq([])
        expect(json['messages_count']).to eq(0)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/ai_agents/{ai_agent.id}/test_conversations/:id' do
    let!(:test_conversation) { create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent) }

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'deletes the test conversation' do
        expect do
          delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}",
                 headers: admin.create_new_auth_token,
                 as: :json
        end.to change(AiAgentTestConversation, :count).by(-1)

        expect(response).to have_http_status(:success)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/{account.id}/ai_agents/{ai_agent.id}/test_conversations/clear_all' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/clear_all"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'deletes all test conversations for the account' do
        create_list(:ai_agent_test_conversation, 3, account: account, ai_agent: ai_agent)
        other_account = create(:account)
        other_ai_agent = create(:ai_agent, account: other_account)
        create(:ai_agent_test_conversation, account: other_account, ai_agent: other_ai_agent)

        expect do
          delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/clear_all",
                 headers: admin.create_new_auth_token,
                 as: :json
        end.to change(AiAgentTestConversation, :count).by(-3)

        expect(response).to have_http_status(:success)
        expect(AiAgentTestConversation.where(account_id: account.id).count).to eq(0)
        expect(AiAgentTestConversation.where(account_id: other_account.id).count).to eq(1)
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/clear_all",
               headers: agent.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/ai_agents/{ai_agent.id}/test_conversations/:id/send_message' do
    let!(:test_conversation) { create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent) }

    before do
      allow(AiAgents::ResponseService).to receive(:new).and_return(
        instance_double(AiAgents::ResponseService, perform: 'Hello from AI')
      )
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             params: { content: 'Hi' }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated administrator' do
      it 'persists user message and returns AI response' do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { content: 'Hello AI' },
             as: :json

        expect(response).to have_http_status(:success)
        json = response.parsed_body
        messages = json['messages']

        expect(messages.length).to eq(2)
        expect(messages.first['role']).to eq('user')
        expect(messages.first['content']).to eq('Hello AI')
        expect(messages.last['role']).to eq('assistant')
        expect(messages.last['content']).to eq('Hello from AI')
        expect(json['title']).to eq('Hello AI')
      end

      it 'persists messages to the database' do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { content: 'Hello AI' },
             as: :json

        test_conversation.reload
        expect(test_conversation.title).to eq('Hello AI')
        expect(test_conversation.messages_count).to eq(2)
      end

      it 'generates title from first user message' do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { content: 'This is a very long first message that should be truncated to fifty characters' },
             as: :json

        expect(response).to have_http_status(:success)
        test_conversation.reload
        expect(test_conversation.title.length).to be <= 50
        expect(test_conversation.title).to start_with('This is a very long first message')
      end

      it 'does not change title if it was already customized' do
        test_conversation.update!(title: 'Custom Title')

        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { content: 'Hello AI' },
             as: :json

        expect(response).to have_http_status(:success)
        test_conversation.reload
        expect(test_conversation.title).to eq('Custom Title')
      end

      it 'returns bad request when content is blank' do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { content: '   ' },
             as: :json

        expect(response).to have_http_status(:bad_request)
        expect(response.parsed_body['error']).to eq('Content is required')
      end

      it 'returns bad request when content is missing' do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: {},
             as: :json

        expect(response).to have_http_status(:bad_request)
      end

      it 'returns 422 when AI service fails to generate a response' do
        allow(AiAgents::ResponseService).to receive(:new).and_return(
          instance_double(AiAgents::ResponseService, perform: nil)
        )

        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { content: 'Hello AI' },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Failed to generate response')
        test_conversation.reload
        expect(test_conversation.messages_count).to eq(1) # user message persisted even on failure
      end
    end

    context 'when the conversation is at the message limit' do
      it 'returns 422 unprocessable entity' do
        max_messages = Array.new(200) do |i|
          { 'id' => SecureRandom.uuid, 'role' => 'user', 'content' => "Message #{i}", 'created_at' => Time.current.iso8601 }
        end
        test_conversation.update!(messages: max_messages)

        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { content: 'One too many' },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Message limit reached (200 messages max)')
      end
    end

    context 'when it is an authenticated agent' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: agent.create_new_auth_token,
             params: { content: 'Hello' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
