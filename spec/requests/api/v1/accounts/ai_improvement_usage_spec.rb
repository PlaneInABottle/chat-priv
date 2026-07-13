require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::AiImprovementUsage', type: :request do
  let(:account) do
    create(:account, settings: { ai_improvement_monthly_credit_limit: 10 })
  end
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/ai_improvement_usage" }

  it 'returns completed and reserved improvement usage to an administrator' do
    text_limiter = AiImprovements::Usage::Limiter.new(account: account, operation: 'text_test')
    text_event = text_limiter.reserve_or_raise!(idempotency_key: 'text-test')
    text_limiter.consume!(text_event, unit_type: 'tokens', units: 1_001)
    AiImprovements::Usage::Limiter.new(account: account, operation: 'website_import')
                                  .reserve_or_raise!(idempotency_key: 'website-import')

    get path, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'period' => 'monthly',
      'limit_credits' => 10,
      'used_credits' => 2,
      'reserved_credits' => 1,
      'remaining_credits' => 7,
      'unlimited' => false,
      'status' => 'ok',
      'breakdown' => { 'text_test' => 2 },
      'rates' => { 'tokens' => 1000, 'embedding_tokens' => 1000, 'audio_seconds' => 10 }
    )
  end

  it 'rejects an authenticated non-admin agent' do
    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'rejects an administrator from another account' do
    foreign_admin = create(:user, account: create(:account), role: :administrator)

    get path, headers: foreign_admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
