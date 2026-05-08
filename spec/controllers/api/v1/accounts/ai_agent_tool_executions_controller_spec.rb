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
      expect(response.parsed_body['meta']['filters']).to include('sort' => 'created_at', 'direction' => 'desc', 'limit' => 25)
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

    it 'returns account, ai agent, and fallback tool display names' do
      create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, tool_key: 'unknown_tool', tool_name: nil)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions", headers: admin.create_new_auth_token, as: :json

      payload = response.parsed_body['payload'].first
      expect(payload).to include('account_name' => account.name, 'ai_agent_name' => ai_agent.name, 'tool_name' => 'Unknown tool')
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

    it 'filters by preset date range' do
      travel_to Time.zone.local(2026, 5, 8, 12, 0, 0) do
        create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, created_at: 2.days.ago)
        matching = create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, created_at: 2.hours.ago)

        get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions",
            headers: admin.create_new_auth_token,
            params: { date_range: '24h' },
            as: :json

        expect(response.parsed_body['payload'].pluck('id')).to eq([matching.id])
      end
    end

    it 'filters by custom date range' do
      create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, created_at: '2026-05-01T12:00:00Z')
      matching = create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, created_at: '2026-05-08T12:00:00Z')

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions",
          headers: admin.create_new_auth_token,
          params: { date_range: 'custom', start_date: '2026-05-08T00:00:00Z', end_date: '2026-05-08T23:59:59Z' },
          as: :json

      expect(response.parsed_body['payload'].pluck('id')).to eq([matching.id])
    end

    it 'ignores invalid custom dates without crashing' do
      execution = create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions",
          headers: admin.create_new_auth_token,
          params: { date_range: 'custom', start_date: 'not-a-date' },
          as: :json

      expect(response).to have_http_status(:success)
      expect(response.parsed_body['payload'].pluck('id')).to eq([execution.id])
      expect(response.parsed_body['meta']['filters']['start_date']).to be_nil
    end

    it 'limits results to the requested bounded size' do
      create_list(:ai_agent_tool_execution, 3, account: account, ai_agent: ai_agent)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions",
          headers: admin.create_new_auth_token,
          params: { limit: 2 },
          as: :json

      expect(response.parsed_body['payload'].size).to eq(2)
    end

    it 'sorts using allowlisted fields and directions' do
      slower = create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, duration_ms: 300)
      faster = create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, duration_ms: 100)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions",
          headers: admin.create_new_auth_token,
          params: { sort: 'duration_ms', direction: 'asc' },
          as: :json

      expect(response.parsed_body['payload'].pluck('id')).to eq([faster.id, slower.id])
    end

    it 'falls back to default sorting for malicious sort params' do
      older = create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, created_at: 1.day.ago)
      newer = create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, created_at: 1.hour.ago)

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/tool_executions",
          headers: admin.create_new_auth_token,
          params: { sort: 'created_at desc; drop table users', direction: 'asc' },
          as: :json

      expect(response.parsed_body['payload'].pluck('id')).to eq([older.id, newer.id])
      expect(response.parsed_body['meta']['filters']['sort']).to eq('created_at')
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
