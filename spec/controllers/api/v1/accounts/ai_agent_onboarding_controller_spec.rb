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
        website_verification_token: 'verified-token'
      },
      assistant: { tone: 'friendly' }
    }
  end

  before do
    allow(AiAgents::OnboardingWebsiteVerifier).to receive(:verified_url!).and_return('https://example.com/')
  end

  it 'verifies a reachable public website before onboarding' do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
    stub_request(:get, 'https://example.com/').to_return(
      status: 200,
      body: '<html><head><title>Example Store</title></head></html>',
      headers: { 'Content-Type' => 'text/html' }
    )

    post "#{base_url}/verify_website", params: { website_url: 'example.com' }, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'website_url' => 'https://example.com/',
      'hostname' => 'example.com',
      'title' => 'Example Store'
    )
    expect(response.parsed_body['verification_token']).to be_present
  end

  it 'returns a recoverable error when the website cannot be opened' do
    allow(AiAgents::OnboardingWebsiteVerifier).to receive(:new).and_raise(SafeFetch::FetchError, 'timeout')

    post "#{base_url}/verify_website", params: { website_url: 'example.com' }, headers: headers, as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'website_unreachable')
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

  it 'rejects an unverified website without creating an assistant' do
    allow(AiAgents::OnboardingWebsiteVerifier).to receive(:verified_url!).and_raise(
      AiAgents::WebsiteCrawler::InvalidWebsite,
      'Website verification is missing or expired.'
    )

    expect do
      post base_url, params: params, headers: headers, as: :json
    end.not_to change(AiAgent, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'invalid_website')
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
