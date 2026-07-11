require 'rails_helper'

RSpec.describe 'Voice agent releases API', type: :request do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:voice_agent) { create(:voice_agent, account: account) }
  let!(:release) { create(:voice_agent_release, voice_agent: voice_agent) }

  it 'lists snapshots separately and creates a rollback revision' do
    voice_agent.update!(current_release: release)

    get "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/releases",
        headers: admin.create_new_auth_token,
        as: :json
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.first).not_to have_key('snapshot')

    get "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/releases/#{release.id}",
        headers: admin.create_new_auth_token,
        as: :json
    expect(response.parsed_body['snapshot']).to eq(release.snapshot)

    post "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/releases/#{release.id}/rollback",
         headers: admin.create_new_auth_token,
         as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('revision' => 2, 'source' => 'rollback')
    expect(voice_agent.reload.current_release_id).to eq(response.parsed_body['id'])
  end
end
