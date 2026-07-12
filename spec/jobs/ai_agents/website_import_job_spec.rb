require 'rails_helper'

RSpec.describe AiAgents::WebsiteImportJob do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:user) { create(:user, account: account) }
  let(:attributes) do
    AiAgents::OnboardingDraftBuilder.new(
      account: account,
      answers: { purpose: 'support', tone: 'friendly', website: 'https://example.com/' }
    ).agent_attributes
  end
  let(:ai_agent) { create(:ai_agent, account: account, **attributes) }
  let(:website_import) do
    create(
      :ai_agent_website_import,
      account: account,
      ai_agent: ai_agent,
      requested_by: user,
      mode: :initial,
      base_draft_fingerprint: ai_agent.draft_fingerprint
    )
  end
  let(:crawl_result) do
    AiAgents::WebsiteCrawler::Result.new(
      pages: [{ url: 'https://example.com/', title: 'Example', text: 'Example sells custom screens.' }],
      source_urls: ['https://example.com/']
    )
  end
  let(:generated_result) do
    AiAgents::WebsiteInstructionGenerator::Result.new(
      sections: { 'business_context' => 'Example sells custom screens.' }
    )
  end

  before do
    crawler = instance_double(AiAgents::WebsiteCrawler, perform: crawl_result)
    generator = instance_double(AiAgents::WebsiteInstructionGenerator, call: generated_result)
    allow(AiAgents::WebsiteCrawler).to receive(:new).and_return(crawler)
    allow(AiAgents::WebsiteInstructionGenerator).to receive(:new).and_return(generator)
  end

  it 'applies an initial import when the fallback draft is unchanged' do
    described_class.perform_now(website_import.id)

    expect(ai_agent.reload.config.dig('instructions', 'sections', 'business_context')).to eq('Example sells custom screens.')
    expect(website_import.reload).to have_attributes(
      status: 'applied',
      stage: 'complete',
      source_urls: ['https://example.com/'],
      proposed_sections: {}
    )
  end

  it 'keeps the proposal ready when the customer changed the draft' do
    website_import
    ai_agent.update!(prompt: "#{ai_agent.prompt}\nCustomer edit")

    described_class.perform_now(website_import.id)

    expect(website_import.reload).to have_attributes(
      status: 'ready',
      proposed_sections: { 'business_context' => 'Example sells custom screens.' }
    )
  end

  it 'keeps the proposal ready when onboarding changed the import to preview mode' do
    website_import.update!(mode: :preview)

    described_class.perform_now(website_import.id)

    expect(ai_agent.reload.config.dig('instructions', 'sections', 'business_context')).not_to eq('Example sells custom screens.')
    expect(website_import.reload).to have_attributes(
      mode: 'preview',
      status: 'ready',
      proposed_sections: { 'business_context' => 'Example sells custom screens.' }
    )
  end

  it 'records a bounded failure and preserves the fallback draft' do
    fallback_prompt = ai_agent.prompt
    allow(AiAgents::WebsiteCrawler).to receive(:new).and_raise(SafeFetch::FetchError, 'timeout')

    described_class.perform_now(website_import.id)

    expect(ai_agent.reload.prompt).to eq(fallback_prompt)
    expect(website_import.reload).to have_attributes(status: 'failed', stage: 'complete', error_code: 'SafeFetch::FetchError')
  end

  it 'does not rerun an import that was already claimed' do
    website_import.update!(status: :ready, stage: :complete)

    expect(AiAgents::WebsiteCrawler).not_to receive(:new)

    described_class.perform_now(website_import.id)

    expect(website_import.reload).to have_attributes(status: 'ready', stage: 'complete')
  end

  it 'does not apply results after the claimed import was expired' do
    fallback_prompt = ai_agent.prompt
    crawler = instance_double(AiAgents::WebsiteCrawler)
    allow(AiAgents::WebsiteCrawler).to receive(:new).and_return(crawler)
    allow(crawler).to receive(:perform) do
      website_import.update!(status: :failed, stage: :complete, error_code: 'stale_import')
      crawl_result
    end

    described_class.perform_now(website_import.id)

    expect(website_import.reload).to have_attributes(status: 'failed', error_code: 'stale_import')
    expect(ai_agent.reload.prompt).to eq(fallback_prompt)
  end
end
