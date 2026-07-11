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
    expect(response.parsed_body).to include('mode' => 'preview', 'status' => 'pending')
  end

  it 'returns recent imports newest first so the editor can resume analysis' do
    older = create(:ai_agent_website_import, account: account, ai_agent: ai_agent, requested_by: admin, created_at: 1.hour.ago)
    newer = create(:ai_agent_website_import, account: account, ai_agent: ai_agent, requested_by: admin, status: :ready)

    get base_url, headers: headers, as: :json

    expect(response).to have_http_status(:success)
    expect(response.parsed_body.pluck('id')).to eq([newer.id, older.id])
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
      base_draft_fingerprint: ai_agent.draft_fingerprint
    )

    post "#{base_url}/#{website_import.id}/apply",
         params: {
           section_keys: ['rules'],
           expected_draft_fingerprint: ai_agent.draft_fingerprint
         },
         headers: headers,
         as: :json

    expect(response).to have_http_status(:success)
    sections = ai_agent.reload.config.dig('instructions', 'sections')
    expect(sections).to include('business_context' => 'Current facts', 'rules' => 'Never promise stock.')
    expect(ai_agent.config.dig('tools', 'enabled')).to include('human_handoff')
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
end
