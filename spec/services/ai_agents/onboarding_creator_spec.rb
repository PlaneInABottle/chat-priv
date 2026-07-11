require 'rails_helper'

RSpec.describe AiAgents::OnboardingCreator do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }, custom_attributes: { 'onboarding_step' => 'account_details' }) }
  let(:user) { create(:user, account: account) }
  let(:account_attributes) do
    {
      locale: 'en',
      website: 'example.com',
      industry: 'E-commerce',
      company_size: '11-50',
      timezone: 'Europe/Istanbul',
      user_role: 'owner'
    }
  end
  let(:assistant_attributes) { { purpose: 'support_and_sales', tone: 'warm' } }

  it 'creates a disabled fallback draft and queues website enrichment' do
    result = nil
    expect do
      result = described_class.new(
        account: account,
        user: user,
        account_attributes: account_attributes,
        assistant_attributes: assistant_attributes
      ).perform
    end.to change(AiAgent, :count).by(1)
       .and change(AiAgentWebsiteImport, :count).by(1)
       .and have_enqueued_job(AiAgents::WebsiteImportJob)

    expect(result.ai_agent).to have_attributes(enabled: false, name: "#{account.name} Assistant")
    expect(result.ai_agent.config.dig('tools', 'enabled')).to include('human_handoff')
    expect(result.ai_agent.config.dig('instructions', 'sections', 'identity')).to be_present
    expect(result.ai_agent.config.dig('instructions', 'sections', 'business_context')).to include('E-commerce')
    expect(result.website_import).to have_attributes(mode: 'initial', website_url: 'https://example.com/')
    expect(account.reload.custom_attributes['onboarding_step']).to eq('ai_assistant')
  end

  it 'creates the fallback without an import when the website is blank' do
    result = described_class.new(
      account: account,
      user: user,
      account_attributes: account_attributes.merge(website: ''),
      assistant_attributes: assistant_attributes
    ).perform

    expect(result.ai_agent).to be_persisted
    expect(result.website_import).to be_nil
  end

  it 'is idempotent for repeated onboarding submissions' do
    service_attributes = {
      account: account,
      user: user,
      account_attributes: account_attributes,
      assistant_attributes: assistant_attributes
    }
    first = described_class.new(**service_attributes).perform

    expect do
      second = described_class.new(**service_attributes).perform
      expect(second.ai_agent).to eq(first.ai_agent)
    end.not_to change(AiAgent, :count)
  end

  it 'creates the starter instructions in Turkish for a Turkish account' do
    result = described_class.new(
      account: account,
      user: user,
      account_attributes: account_attributes.merge(locale: 'tr', website: ''),
      assistant_attributes: assistant_attributes
    ).perform

    expect(result.ai_agent.name).to eq("#{account.name} Asistanı")
    expect(result.ai_agent.config.dig('instructions', 'sections', 'identity')).to include('Yalnızca doğrulanmış')
    expect(result.ai_agent.config.dig('instructions', 'sections', 'handoff')).to include('bir insana aktar')
  end
end
