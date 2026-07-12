require 'rails_helper'

RSpec.describe 'AI Agent Evaluations API', type: :request do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:ai_agent) { create(:ai_agent, account: account, prompt: 'Current draft') }

  describe 'evaluation cases' do
    it 'lets an administrator create, update, list, and delete a scenario' do
      post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/evaluation_cases",
           params: {
             name: 'Delivery question',
             customer_message: 'When will it arrive?',
             success_criteria: 'Do not promise an exact date.'
           },
           headers: administrator.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      evaluation_case_id = response.parsed_body.fetch('id')

      patch "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/evaluation_cases/#{evaluation_case_id}",
            params: { name: 'Updated delivery question' },
            headers: administrator.create_new_auth_token,
            as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['name']).to eq('Updated delivery question')

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/evaluation_cases",
          headers: administrator.create_new_auth_token,
          as: :json
      expect(response.parsed_body.pluck('id')).to eq([evaluation_case_id])

      delete "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/evaluation_cases/#{evaluation_case_id}",
             headers: administrator.create_new_auth_token,
             as: :json
      expect(response).to have_http_status(:no_content)
    end

    it 'rejects non-administrators' do
      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/evaluation_cases",
          headers: agent_user.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'limits an assistant to twenty scenarios' do
      create_list(:ai_agent_evaluation_case, 20, account: account, ai_agent: ai_agent)

      post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/evaluation_cases",
           params: {
             name: 'One too many',
             customer_message: 'Hello',
             success_criteria: 'Reply politely.'
           },
           headers: administrator.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('up to 20')
    end
  end

  describe 'evaluation runs' do
    let!(:evaluation_case) do
      create(:ai_agent_evaluation_case, account: account, ai_agent: ai_agent)
    end

    it 'snapshots the current draft and enqueues a run' do
      source = create(:ai_knowledge_source, account: account, name: 'Returns')
      AiKnowledgeSourceAssignment.create!(assistant: ai_agent, ai_knowledge_source: source)

      expect do
        post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/evaluation_runs",
             headers: administrator.create_new_auth_token,
             as: :json
      end.to have_enqueued_job(AiAgents::EvaluationRunJob)

      expect(response).to have_http_status(:accepted)
      expect(response.parsed_body).to include(
        'status' => 'pending',
        'total_count' => 1,
        'passed_count' => 0,
        'current_draft' => true
      )
      expect(response.parsed_body.dig('results', 0)).to include(
        'evaluation_case_id' => evaluation_case.id,
        'customer_message' => evaluation_case.customer_message,
        'success_criteria' => evaluation_case.success_criteria
      )
      expect(AiAgentEvaluationRun.last).to have_attributes(
        prompt_snapshot: 'Current draft',
        draft_fingerprint: ai_agent.draft_fingerprint
      )
      expect(AiAgentEvaluationRun.last.knowledge_snapshot).to contain_exactly(
        include('id' => source.id, 'name' => 'Returns', 'content' => source.content)
      )
    end

    it 'rejects another run while one is pending' do
      create(:ai_agent_evaluation_run, account: account, ai_agent: ai_agent)

      post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/evaluation_runs",
           headers: administrator.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to include('already in progress')
    end

    it 'marks completed results as belonging to an older draft after an edit' do
      evaluation_run = create(
        :ai_agent_evaluation_run,
        :completed,
        account: account,
        ai_agent: ai_agent
      )
      create(
        :ai_agent_evaluation_result,
        evaluation_run: evaluation_run,
        evaluation_case: evaluation_case,
        status: :completed,
        passed: false
      )
      ai_agent.update!(prompt: 'Edited after evaluation')

      get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/evaluation_runs/#{evaluation_run.id}",
          headers: administrator.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['current_draft']).to be(false)
      expect(response.parsed_body['failed_count']).to eq(1)
    end
  end
end
