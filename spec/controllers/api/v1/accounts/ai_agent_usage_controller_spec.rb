require 'rails_helper'

RSpec.describe 'Ai Agent Usage API', type: :request do
  let!(:account) { create(:account, settings: { ai_agent_enabled: true, ai_agent_conversation_limit: 10, ai_agent_conversation_reuse_window_hours: 24 }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:ai_agent) { create(:ai_agent, account: account) }

  describe 'GET /api/v1/accounts/{account.id}/ai_agent_usage' do
    it 'returns usage summary for an authenticated administrator' do
      create(:ai_agent_usage_event, account: account, ai_agent: ai_agent, status: :consumed)

      get "/api/v1/accounts/#{account.id}/ai_agent_usage", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to include(
        'period' => 'monthly',
        'limit' => 10,
        'used' => 1,
        'remaining' => 9,
        'unlimited' => false,
        'reuse_window_hours' => 24
      )
      expect(response.parsed_body).not_to have_key('model')
      expect(response.parsed_body).not_to have_key('ai_agent_model')
    end

    it 'excludes simulator calls from live usage metrics' do
      conversation = create(:conversation, account: account)
      message = create(:message, account: account, conversation: conversation)
      create(:ai_agent_llm_call, account: account, ai_agent: ai_agent, mode: :test, message: message)
      create(:ai_agent_llm_call, account: account, ai_agent: ai_agent, mode: :live, message: message)
      create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, mode: :test, message: message)
      create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, mode: :live, message: message)

      get "/api/v1/accounts/#{account.id}/ai_agent_usage", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body.dig('metrics', 'ai_replies')).to eq(1)
      expect(response.parsed_body.dig('metrics', 'tool_calls')).to eq(1)
    end

    it 'rejects an authenticated agent' do
      get "/api/v1/accounts/#{account.id}/ai_agent_usage", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns forbidden when AI Agent is disabled for the account' do
      account.update!(ai_agent_enabled: false)

      get "/api/v1/accounts/#{account.id}/ai_agent_usage", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end
  end
end
