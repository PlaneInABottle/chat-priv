require 'rails_helper'

RSpec.describe 'AI Knowledge Sources API', type: :request do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, role: :agent) }
  let(:headers) { administrator.create_new_auth_token }

  it 'creates a website source and enqueues its first sync' do
    expect do
      post "/api/v1/accounts/#{account.id}/ai_knowledge_sources",
           params: { name: 'Store policies', source_type: 'website', website_url: 'example.com/policies' },
           headers: headers,
           as: :json
    end.to have_enqueued_job(AiKnowledgeSources::WebsiteSyncJob)

    expect(response).to have_http_status(:created)
    expect(response.parsed_body).to include(
      'name' => 'Store policies',
      'source_type' => 'website',
      'website_url' => 'https://example.com/policies',
      'sync_status' => 'pending',
      'available' => false,
      'content' => ''
    )
  end

  it 'returns freshness metadata without full content in the collection' do
    source = create(
      :ai_knowledge_source,
      :website,
      account: account,
      content: 'Verified return policy',
      sync_status: :ready,
      source_urls: ['https://example.com/returns'],
      last_synced_at: 1.hour.ago
    )

    get "/api/v1/accounts/#{account.id}/ai_knowledge_sources", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    payload = response.parsed_body.find { |item| item['id'] == source.id }
    expect(payload).to include(
      'sync_status' => 'ready',
      'available' => true,
      'source_urls' => ['https://example.com/returns'],
      'content_preview' => 'Verified return policy'
    )
    expect(payload).not_to have_key('content')
  end

  it 'queues a manual resync and rejects duplicate requests' do
    source = create(:ai_knowledge_source, :website, account: account, content: 'Last-known-good content', sync_status: :ready)

    expect do
      post "/api/v1/accounts/#{account.id}/ai_knowledge_sources/#{source.id}/sync", headers: headers, as: :json
    end.to have_enqueued_job(AiKnowledgeSources::WebsiteSyncJob).with(source.id)

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body['sync_status']).to eq('pending')

    post "/api/v1/accounts/#{account.id}/ai_knowledge_sources/#{source.id}/sync", headers: headers, as: :json

    expect(response).to have_http_status(:conflict)
  end

  it 'does not allow manual sources to be synced' do
    source = create(:ai_knowledge_source, account: account)

    post "/api/v1/accounts/#{account.id}/ai_knowledge_sources/#{source.id}/sync", headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'keeps sources account scoped and administrator only' do
    foreign_source = create(:ai_knowledge_source)

    get "/api/v1/accounts/#{account.id}/ai_knowledge_sources/#{foreign_source.id}", headers: headers, as: :json
    expect(response).to have_http_status(:not_found)

    get "/api/v1/accounts/#{account.id}/ai_knowledge_sources", headers: agent_user.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
  end
end
