require 'rails_helper'

RSpec.describe AiAgents::WebsiteImportJob do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:user) { create(:user, account: account) }
  let(:attributes) do
    AiAgents::OnboardingDraftBuilder.new(
      account: account,
      answers: { tone: 'friendly', website: 'https://example.com/' }
    ).agent_attributes
  end
  let(:ai_agent) { create(:ai_agent, account: account, **attributes) }
  let(:website_import) do
    create(
      :ai_agent_website_import,
      account: account,
      ai_agent: ai_agent,
      requested_by: user,
      base_draft_fingerprint: ai_agent.draft_fingerprint
    )
  end
  let(:crawl_result) do
    AiAgents::WebsiteCrawler::Result.new(
      pages: [{ url: 'https://example.com/', title: 'Example', text: 'Example sells custom screens.' }],
      source_urls: ['https://example.com/'],
      knowledge_content: "# Example\nSource: https://example.com/\nExample sells custom screens."
    )
  end
  let(:generated_result) do
    AiAgents::WebsiteInstructionGenerator::Result.new(
      sections: { 'business_context' => 'Example sells custom screens.' }
    )
  end

  let(:generator) { instance_double(AiAgents::WebsiteInstructionGenerator, call: generated_result) }

  before do
    crawler = instance_double(AiAgents::WebsiteCrawler, perform: crawl_result)
    allow(AiAgents::WebsiteCrawler).to receive(:new).and_return(crawler)
    allow(AiAgents::WebsiteInstructionGenerator).to receive(:new).and_return(generator)
  end

  it 'keeps generated instructions and knowledge ready for explicit review' do
    described_class.perform_now(website_import.id)

    expect(ai_agent.reload.config.dig('instructions', 'sections', 'business_context')).not_to eq('Example sells custom screens.')
    expect(website_import.reload).to have_attributes(
      status: 'ready',
      stage: 'complete',
      source_urls: ['https://example.com/'],
      proposed_sections: { 'business_context' => 'Example sells custom screens.' },
      proposed_knowledge_content: "# Example\nSource: https://example.com/\nExample sells custom screens."
    )
    expect(AiAgents::WebsiteInstructionGenerator).to have_received(:new)
    expect(generator).to have_received(:call).with(
      pages: crawl_result.pages,
      business_context: { company_name: account.name }
    )
  end

  it 'continues with the timestamp persisted by the database' do
    website_import
    precise_now = Time.at(1_800_000_000, Rational(123_456_789, 1_000)).utc
    allow(Time).to receive(:current).and_return(precise_now)

    described_class.perform_now(website_import.id)

    expect(website_import.reload).to be_ready
    expect(website_import.started_at.nsec).to eq(123_456_000)
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

  it 'records a bounded failure when the import could not be claimed' do
    job = described_class.new(website_import.id)
    allow(job).to receive(:start_import).and_raise(
      ActiveRecord::DatabaseConnectionError.hostname_error('127.0.0.1')
    )

    expect { job.perform_now }.not_to raise_error

    expect(website_import.reload).to have_attributes(
      status: 'failed',
      stage: 'complete',
      error_code: 'ActiveRecord::DatabaseConnectionError',
      error_message: /127\.0\.0\.1/
    )
  end

  context 'when the import record cannot be loaded' do
    after { allow(AiAgentWebsiteImport).to receive(:find).and_call_original }

    it 'surfaces a transient connection failure before the import is loaded so Sidekiq can retry' do
      allow(AiAgentWebsiteImport).to receive(:find).and_raise(
        ActiveRecord::DatabaseConnectionError.hostname_error('127.0.0.1')
      )

      expect { described_class.perform_now(website_import.id) }.to raise_error(ActiveRecord::DatabaseConnectionError)

      expect(website_import.reload).to have_attributes(status: 'pending', stage: 'queued', started_at: nil)
    end

    it 'stays silent when the import record was deleted while queued' do
      allow(AiAgentWebsiteImport).to receive(:find).and_raise(ActiveRecord::RecordNotFound)

      expect { described_class.perform_now(website_import.id) }.not_to raise_error
    end
  end
end
