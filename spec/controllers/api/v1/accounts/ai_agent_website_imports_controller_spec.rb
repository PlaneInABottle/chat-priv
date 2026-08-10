require 'rails_helper'

RSpec.describe 'AI agent website imports API', type: :request do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:ai_agent) do
    create(
      :ai_agent,
      account: account,
      config: {
        'instructions' => AiAgents::InstructionDocument.new(
          'sections' => { 'business_context' => 'Current facts' }
        ).normalized,
        'tools' => { 'enabled' => ['human_handoff'] }
      }
    )
  end
  let(:base_url) { "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/website_imports" }

  it 'starts a preview import' do
    expect do
      post base_url, params: { website_url: 'example.com' }, headers: headers, as: :json
    end.to change(AiAgentWebsiteImport, :count).by(1).and have_enqueued_job(AiAgents::WebsiteImportJob)

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to include('status' => 'pending', 'has_review_context' => true)
  end

  it 'returns a structured rate-limit response' do
    create(:ai_agent_website_import, account: account, ai_agent: ai_agent, requested_by: admin, status: :failed, created_at: 5.seconds.ago)

    post base_url, params: { website_url: 'another.example.com' }, headers: headers, as: :json

    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to include('code' => 'website_import_rate_limited')
    expect(response.parsed_body['retry_after']).to be_between(1, 30)
  end

  it 'returns safe failure details and the current instruction document' do
    website_import = create(
      :ai_agent_website_import,
      account: account,
      ai_agent: ai_agent,
      requested_by: admin,
      status: :failed,
      error_code: 'SafeFetch::FetchError',
      error_message: 'Connection refused by 10.0.0.4'
    )

    get "#{base_url}/#{website_import.id}", headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body).to include('error_code' => 'website_unreachable')
    expect(response.parsed_body).not_to have_key('error_message')
    expect(response.parsed_body.dig('base_document', 'sections', 'business_context')).to eq('Current facts')
  end

  it 'returns recent imports newest first so the editor can resume analysis' do
    older = create(:ai_agent_website_import, account: account, ai_agent: ai_agent, requested_by: admin, created_at: 1.hour.ago)
    newer = create(
      :ai_agent_website_import,
      account: account,
      ai_agent: ai_agent,
      requested_by: admin,
      status: :ready,
      proposed_sections: { 'rules' => 'New rules', 'identity' => 'New identity' }
    )

    get base_url, headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.pluck('id')).to eq([newer.id, older.id])
    expect(response.parsed_body.first).to have_key('base_document')
    expect(response.parsed_body.second).not_to have_key('base_document')
  end

  it 'applies only selected sections to the saved draft' do
    website_import = create(
      :ai_agent_website_import,
      account: account,
      ai_agent: ai_agent,
      requested_by: admin,
      status: :ready,
      stage: :complete,
      proposed_sections: {
        'business_context' => 'New facts',
        'rules' => 'Never promise stock.'
      },
      proposed_knowledge_content: "# Example\nVerified website facts.",
      base_draft_fingerprint: ai_agent.draft_fingerprint
    )

    post "#{base_url}/#{website_import.id}/apply",
         params: {
           section_keys: ['rules'],
           current_document: ai_agent.config['instructions'],
           attach_knowledge: true,
           expected_draft_fingerprint: ai_agent.draft_fingerprint
         },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:success)
    sections = ai_agent.reload.config.dig('instructions', 'sections')
    expect(sections).to include('business_context' => 'Current facts', 'rules' => 'Never promise stock.')
    expect(ai_agent.config.dig('tools', 'enabled')).to include('human_handoff')
    expect(ai_agent.knowledge_sources.first).to have_attributes(source_type: 'website', sync_status: 'ready')
  end

  it 'returns a validation response when website knowledge would exceed the source limit' do
    sources = create_list(:ai_knowledge_source, AiKnowledgeSources::AssignmentSync::MAX_SOURCES, account: account)
    AiKnowledgeSources::AssignmentSync.new(assistant: ai_agent, source_ids: sources.map(&:id)).perform
    website_import = create(
      :ai_agent_website_import,
      account: account,
      ai_agent: ai_agent,
      requested_by: admin,
      status: :ready,
      stage: :complete,
      proposed_knowledge_content: "# Example\nVerified website facts.",
      base_draft_fingerprint: ai_agent.draft_fingerprint
    )

    post "#{base_url}/#{website_import.id}/apply",
         params: {
           section_keys: [],
           attach_knowledge: true,
           expected_draft_fingerprint: ai_agent.draft_fingerprint
         },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'knowledge_source_limit')
    expect(website_import.reload).to be_ready
    expect(ai_agent.reload.knowledge_source_ids).to match_array(sources.map(&:id))
  end

  it 'returns a conflict when the draft changed after preview generation' do
    website_import = create(
      :ai_agent_website_import,
      account: account,
      ai_agent: ai_agent,
      requested_by: admin,
      status: :ready,
      proposed_sections: { 'rules' => 'Use verified facts.' },
      base_draft_fingerprint: ai_agent.draft_fingerprint
    )
    old_fingerprint = ai_agent.draft_fingerprint
    ai_agent.update!(prompt: "#{ai_agent.prompt}\nCustomer edit")

    post "#{base_url}/#{website_import.id}/apply",
         params: { section_keys: ['rules'], expected_draft_fingerprint: old_fingerprint },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:conflict)
    expect(response.parsed_body['code']).to eq('draft_changed')
  end

  describe 'shared workspace credit pool boundaries' do
    before do
      account.update!(ai_improvement_monthly_credit_limit: Account::FREEMIUM_AI_IMPROVEMENT_MONTHLY_CREDIT_LIMIT)
    end

    it 'admits an import at 599 used credits and returns the 402 contract at 600 across operations' do
      period = AiAgents::Usage::Period.new(account: account, now: Time.current)
      fill_improvement_credits = lambda do |credits|
        # Seed through a different operation to prove the shared pool, not an isolated balance.
        AiImprovementUsageEvent.create!(
          account: account, operation: 'text_test', unit_type: 'tokens', units: credits * 1_000, credits: credits,
          status: :consumed, period_start_at: period.start_at, period_end_at: period.end_at,
          idempotency_key: "website-import-boundary-#{credits}"
        )
      end

      fill_improvement_credits.call(599)

      expect do
        post base_url, params: { website_url: 'example.com' }, headers: headers, as: :json
      end.to change(AiAgentWebsiteImport, :count).by(1).and have_enqueued_job(AiAgents::WebsiteImportJob)
      expect(response).to have_http_status(:accepted)

      fill_improvement_credits.call(1)

      expect do
        post base_url, params: { website_url: 'example.com' }, headers: headers, as: :json
      end.not_to change(AiAgentWebsiteImport, :count)
      expect do
        post base_url, params: { website_url: 'example.com' }, headers: headers, as: :json
      end.not_to have_enqueued_job(AiAgents::WebsiteImportJob)

      expect(response).to have_http_status(:payment_required)
      expect(response.parsed_body).to include('code' => 'ai_improvement_credits_exhausted')
      expect(response.parsed_body['usage']).to include('remaining_credits' => 0)
    end
  end
end
