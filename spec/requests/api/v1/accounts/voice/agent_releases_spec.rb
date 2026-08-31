require 'rails_helper'

RSpec.describe 'Voice agent releases API', type: :request do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:voice_agent) { create(:voice_agent, account: account) }
  let!(:release) { create(:voice_agent_release, voice_agent: voice_agent) }
  let(:headers) { admin.create_new_auth_token }
  let(:canonical_profile) { { 'tone' => 'professional', 'business_context' => 'Canonical', 'boundaries' => '' } }
  let(:contaminated_snapshot) do
    release.snapshot.deep_merge(
      'prompt' => 'Historical prompt',
      'config' => { 'runtime' => 'historical', 'authoring_profile' => { 'tone' => 'concise' } }
    )
  end
  let(:sanitized_snapshot) { VoiceAgents::ReleaseSnapshot.sanitize(contaminated_snapshot) }

  before do
    voice_agent.update!(
      current_release: release,
      config: { 'runtime' => 'current', 'authoring_profile' => canonical_profile }
    )
    release.update!(
      snapshot: contaminated_snapshot,
      fingerprint: AssistantReleases::Snapshot.fingerprint(contaminated_snapshot)
    )
  end

  it 'keeps release index responses snapshot-free' do
    get "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/releases", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.first).not_to have_key('snapshot')
  end

  it 'sanitizes contaminated historical snapshots in show responses' do
    get "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/releases/#{release.id}", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['snapshot']).to eq(sanitized_snapshot)
    expect(response.parsed_body.dig('snapshot', 'config')).not_to have_key('authoring_profile')
  end

  it 'creates and returns an exactly sanitized rollback while preserving the canonical profile' do
    post "/api/v1/accounts/#{account.id}/voice/agents/#{voice_agent.id}/releases/#{release.id}/rollback",
         headers: headers,
         as: :json

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include('revision' => 2, 'source' => 'rollback', 'snapshot' => sanitized_snapshot)
    restored = voice_agent.releases.find(response.parsed_body['id'])
    expect(restored.snapshot).to eq(sanitized_snapshot)
    expect(restored.fingerprint).to eq(AssistantReleases::Snapshot.fingerprint(restored.snapshot))
    expect(voice_agent.reload).to have_attributes(current_release: restored, enabled: true, prompt: 'Historical prompt')
    expect(voice_agent.authoring_profile).to eq(canonical_profile)
    expect(voice_agent.runtime_config).to eq('runtime' => 'historical')
  end
end
