require 'rails_helper'

RSpec.describe 'Ai Agent Test Conversations API', type: :request do
  let!(:account) { create(:account, settings: { ai_agent_enabled: true }) }
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

    context 'when AI Agent is disabled for the account' do
      before { account.update!(ai_agent_enabled: false) }

      it 'returns forbidden for an authenticated administrator' do
        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations",
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body['error']).to eq('AI Agent is not enabled for this account')
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

    let(:assistant_message) do
      {
        'id' => SecureRandom.uuid,
        'role' => 'assistant',
        'content' => 'Hello from AI',
        'created_at' => Time.current.iso8601(3),
        'tool_events' => []
      }
    end

    before do
      allow(AiAgents::Orchestrator).to receive(:new).and_return(
        instance_double(AiAgents::Orchestrator, perform: {
          assistant_message: assistant_message,
          tool_events: [],
          terminal_action: nil
        })
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

      it 'tests structured draft instructions without changing the saved prompt' do
        ai_agent.update!(prompt: 'Saved live instructions')
        draft_instructions = {
          version: 3,
          profile: {
            language: 'tr',
            tone: 'friendly',
            formality: 'not_set',
            response_length: 'short'
          },
          sections: { rules: 'Never invent a price.' }
        }
        compiled_prompt = AiAgents::InstructionDocument.new(draft_instructions).compile

        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { content: 'How much?', draft_instructions: draft_instructions },
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['tested_draft']).to be(true)
        expect(AiAgents::Orchestrator).to have_received(:new).with(
          hash_including(ai_agent: ai_agent, prompt_override: compiled_prompt)
        )
        expect(ai_agent.reload.prompt).to eq('Saved live instructions')
        expected_digest = ai_agent.send(:release_digest, compiled_prompt, ai_agent.config)
        expect(ai_agent.last_tested_prompt_digest).to eq(expected_digest)
      end

      it 'does not count simulator messages against AI usage limits' do
        expect do
          post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
               headers: admin.create_new_auth_token,
               params: { content: 'Hello AI' },
               as: :json
        end.not_to change(AiAgentUsageEvent, :count)

        expect(response).to have_http_status(:success)
      end

      it 'generates a response for agents with legacy human handoff config keys' do
        ai_agent.update_columns(enabled: true, config: {
                                 'tools' => {
                                   'enabled' => ['human_handoff'],
                                   'human_handoff' => {
                                     'allowed_labels' => ['vip'],
                                     'preview_only' => true,
                                     'transfer_message' => 'Please wait.'
                                   }
                                 }
                               })
        adapter = instance_double(AiAgents::LlmAdapters::OpenAiCompatibleAdapter)
        allow(adapter).to receive(:perform).and_return({ assistant_text: 'Hello from AI', tool_calls: [], finish_reason: 'stop' })
        allow(AiAgents::LlmAdapters::OpenAiCompatibleAdapter).to receive(:new).and_return(adapter)
        allow(AiAgents::Orchestrator).to receive(:new).and_call_original

        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { content: 'Hello AI' },
             as: :json

        expect(response.parsed_body['error']).to be_nil
        expect(response).to have_http_status(:success)
        expect(response.parsed_body['messages'].last['content']).to eq('Hello from AI')
      end

      it 'persists additive tool metadata for simulator handoff results' do
        allow(AiAgents::Orchestrator).to receive(:new).and_return(
          instance_double(AiAgents::Orchestrator, perform: {
            assistant_message: assistant_message.merge(
              'content' => 'Transferring to another agent for further assistance.',
              'tool_events' => [{ 'tool' => 'human_handoff', 'status' => 'ok' }],
              'terminal_action' => 'handoff',
               'tool_result' => {
                  'customer_message' => 'Transferring to another agent for further assistance.',
                  'private_note_preview' => 'Escalate to billing',
                  'labels_requested' => ['vip', 'ignored'],
                  'labels_to_apply' => ['vip'],
                  'labels_ignored' => ['ignored'],
                  'conversation_status' => 'open'
                }
              ),
            tool_events: [{ 'tool' => 'human_handoff', 'status' => 'ok' }],
            terminal_action: 'handoff'
          })
        )

        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { content: 'Need a person' },
             as: :json

        expect(response).to have_http_status(:success)
        assistant_reply = response.parsed_body['messages'].last
        expect(assistant_reply['terminal_action']).to eq('handoff')
        expect(assistant_reply['tool_events']).to eq([{ 'tool' => 'human_handoff', 'status' => 'ok' }])
        expect(assistant_reply.dig('tool_result', 'customer_message')).to eq('Transferring to another agent for further assistance.')
        expect(assistant_reply.dig('tool_result', 'private_note_preview')).to eq('Escalate to billing')
        expect(assistant_reply.dig('tool_result', 'labels_requested')).to eq(%w[vip ignored])
        expect(assistant_reply.dig('tool_result', 'labels_to_apply')).to eq(['vip'])
        expect(assistant_reply.dig('tool_result', 'labels_ignored')).to eq(['ignored'])
        expect(assistant_reply.dig('tool_result', 'conversation_status')).to eq('open')
      end

      it 'accepts a stored option click as the next simulated customer message' do
        prompt = test_conversation.append_message(
          role: 'assistant',
          content: 'Nasıl devam edelim?',
          metadata: {
            terminal_action: 'present_options',
            tool_result: {
              presentation: {
                content_type: 'input_select',
                items: [
                  { title: 'Ürün seçimi', value: 'products' },
                  { title: 'Sipariş desteği', value: 'orders' }
                ]
              }
            }
          }
        )

        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
             headers: admin.create_new_auth_token,
             params: { reply_to_message_id: prompt['id'], selected_value: 'orders' },
             as: :json

        expect(response).to have_http_status(:success)
        messages = response.parsed_body['messages']
        expect(messages.first['submitted_values']).to eq([{ 'title' => 'Sipariş desteği', 'value' => 'orders' }])
        expect(messages.second).to include('role' => 'user', 'content' => 'Sipariş desteği')
        expect(messages.last).to include('role' => 'assistant', 'content' => 'Hello from AI')
      end

      it 'rejects a stale or unknown simulated option without appending a message' do
        prompt = test_conversation.append_message(
          role: 'assistant',
          content: 'Choose',
          metadata: {
            terminal_action: 'present_options',
            tool_result: { presentation: { content_type: 'input_select', items: [{ title: 'Sales', value: 'sales' }] } }
          }
        )

        expect do
          post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/test_conversations/#{test_conversation.id}/send_message",
               headers: admin.create_new_auth_token,
               params: { reply_to_message_id: prompt['id'], selected_value: 'unknown' },
               as: :json
        end.not_to(change { test_conversation.reload.messages_count })

        expect(response).to have_http_status(:unprocessable_entity)
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
        allow(AiAgents::Orchestrator).to receive(:new).and_return(
          instance_double(AiAgents::Orchestrator, perform: { assistant_message: nil, tool_events: [], terminal_action: nil })
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
