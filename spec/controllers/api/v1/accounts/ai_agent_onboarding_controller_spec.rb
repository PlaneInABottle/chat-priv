require 'rails_helper'

RSpec.describe 'AI agent onboarding API', type: :request do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }, custom_attributes: { onboarding_step: 'account_details' }) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:base_url) { "/api/v1/accounts/#{account.id}/ai_agent_onboarding" }
  let(:params) do
    {
      account: {
        locale: 'en',
        website: 'example.com',
        industry: 'Retail & E-commerce',
        company_size: '1-10',
        timezone: 'Europe/Istanbul',
        referral_source: 'google',
        user_role: 'founder'
      },
      assistant: { tone: 'warm' }
    }
  end

  it 'creates a private fallback assistant and starts website analysis' do
    expect do
      post base_url, params: params, headers: headers, as: :json
    end.to change(AiAgent, :count).by(1)
       .and change(AiAgentWebsiteImport, :count).by(1)
       .and have_enqueued_job(AiAgents::WebsiteImportJob)

    expect(response).to have_http_status(:accepted)
    expect(response.parsed_body).to include('status' => 'pending', 'onboarding_step' => nil)
    expect(account.ai_agents.first).not_to be_enabled
    expect(account.ai_agents.first.config.dig('tools', 'enabled')).to include('human_handoff')
  end

  it 'creates the fallback without a website import when the website is omitted' do
    params[:account][:website] = ''

    expect do
      post base_url, params: params, headers: headers, as: :json
    end.to change(AiAgent, :count).by(1).and not_change(AiAgentWebsiteImport, :count)

    expect(response.parsed_body['status']).to eq('fallback')
  end

  it 'returns a structured rate limit when a failed onboarding import is retried immediately' do
    post base_url, params: params, headers: headers, as: :json
    account.ai_agent_website_imports.last.update!(status: :failed, stage: :complete)

    post base_url, params: params, headers: headers, as: :json

    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to include('code' => 'website_import_rate_limited')
  end

  it 'completes onboarding in the create request and leaves website findings for review' do
    post base_url, params: params, headers: headers, as: :json

    expect(response).to have_http_status(:accepted)
    expect(account.reload.onboarding_step).to be_nil
    expect(account.ai_agent_website_imports.last).to have_attributes(status: 'pending')
    expect(account.ai_agent_website_imports.last.base_document).to be_present
  end

  it 'rejects non-administrators' do
    agent = create(:user, account: account, role: :agent)

    post base_url, params: params, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end
end
