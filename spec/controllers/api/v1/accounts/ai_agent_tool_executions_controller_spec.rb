require 'rails_helper'

RSpec.describe 'Ai Agent Tool Executions API', type: :request do
  let!(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:ai_agent) { create(:ai_agent, account: account) }

  describe 'GET /api/v1/accounts/{account.id}/ai_agents/{ai_agent.id}/tool_executions' do
    it 'returns unauthorized when unauthenticated' do
      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions"

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns current account tool executions for administrators' do
      execution = create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, arguments: { 'reason' => 'Need help' })

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].first).to include('id' => execution.id, 'tool_key' => 'human_handoff',
                                                               'arguments' => { 'reason' => 'Need help' })
    end

    it 'denies non-administrator users through the parent AI agent policy' do
      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'returns not found for cross-account AI agent IDs' do
      other_ai_agent = create(:ai_agent)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{other_ai_agent.id}/tool_executions", headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'excludes cross-account log rows even if associated IDs are guessed' do
      create(:ai_agent_tool_execution)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions", headers: admin.create_new_auth_token, as: :json

      expect(response.parsed_body['payload']).to eq([])
    end

    it 'returns conversation display id and dashboard URL' do
      conversation = create(:conversation, account: account)
      create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, conversation: conversation)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions", headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].first
      expect(payload['conversation_display_id']).to eq(conversation.display_id)
      expect(payload['conversation_url']).to eq("/app/accounts/#{account.id}/conversations/#{conversation.display_id}")
    end

    it 'filters by status, mode, and tool key' do
      create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, status: :executed, mode: :test, tool_key: 'human_handoff')
      matching = create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, status: :error, mode: :live, tool_key: 'ikas_lookup_order')

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions",
          headers: admin.create_new_auth_token,
          params: { status: 'error', mode: 'live', tool_key: 'ikas_lookup_order' },
          as: :json

      expect(response.parsed_body['payload'].pluck('id')).to eq([matching.id])
    end

    it 'limits results to the requested bounded size' do
      create_list(:ai_agent_tool_execution, 3, account: account, ai_agent: ai_agent)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions",
          headers: admin.create_new_auth_token,
          params: { limit: 2 },
          as: :json

      expect(response.parsed_body['payload'].size).to eq(2)
    end

    it 'clamps the requested limit to the maximum size' do
      create_list(:ai_agent_tool_execution, 101, account: account, ai_agent: ai_agent)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions",
          headers: admin.create_new_auth_token,
          params: { limit: 101 },
          as: :json

      expect(response.parsed_body['payload'].size).to eq(100)
    end
  end
end
