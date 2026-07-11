require 'rails_helper'

RSpec.describe 'AI agent releases API', type: :request do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let!(:release) { create(:ai_agent_release, ai_agent: ai_agent) }

  it 'lists release metadata and exposes a selected snapshot' do
    get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/releases",
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.first).to include('id' => release.id, 'revision' => 1, 'source' => 'publish')
    expect(response.parsed_body.first).not_to have_key('snapshot')

    get "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/releases/#{release.id}",
        headers: admin.create_new_auth_token,
        as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['snapshot']).to eq(release.snapshot)
  end

  it 'rolls back account-owned releases and rejects cross-account releases' do
    ai_agent.update!(current_release: release, published_revision: 1)
    foreign_release = create(:ai_agent_release)

    post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/releases/#{foreign_release.id}/rollback",
         headers: admin.create_new_auth_token,
         as: :json
    expect(response).to have_http_status(:not_found)

    post "/api/v1/accounts/#{account.id}/ai_agents/#{ai_agent.id}/releases/#{release.id}/rollback",
         headers: admin.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('revision' => 2, 'source' => 'rollback')
    expect(ai_agent.reload.current_release_id).to eq(response.parsed_body['id'])
  end
end
