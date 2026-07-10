require 'rails_helper'

RSpec.describe 'AI data retention API', type: :request do
  let(:account) do
    create(
      :account,
      ai_agent_data_retention_days: 30,
      voice_ai_data_retention_days: 90
    )
  end
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:endpoint) { "/api/v1/accounts/#{account.id}/ai_data_retention" }

  it 'returns separate text and voice policies to administrators' do
    get endpoint, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq(
      'text' => { 'days' => 30 },
      'voice' => { 'days' => 90 },
      'allowed_days' => [7, 30, 90, 180, 365]
    )
  end

  it 'rejects authenticated agents' do
    get endpoint, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'updates only supported policy values' do
    patch endpoint, params: { kind: 'text', days: 180 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
    expect(account.reload.ai_agent_data_retention_days).to eq(180)

    patch endpoint, params: { kind: 'text', days: 14 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(account.reload.ai_agent_data_retention_days).to eq(180)
  end

  it 'queues cleanup for the requested AI mode' do
    expect do
      post "#{endpoint}/purge", params: { kind: 'voice' }, headers: admin.create_new_auth_token, as: :json
    end.to have_enqueued_job(AiDataRetention::PurgeAccountJob).with(account.id, 'voice')

    expect(response).to have_http_status(:accepted)
  end
end
