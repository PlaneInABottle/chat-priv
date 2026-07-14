require 'rails_helper'

RSpec.describe AiKnowledgeSources::WebsiteSyncJob do
  let(:source) { create(:ai_knowledge_source, :website) }
  let(:crawler) { instance_double(AiAgents::WebsiteCrawler) }
  let(:pages) do
    [
      {
        url: 'https://example.com/',
        title: 'Example policies',
        text: 'Returns are accepted within 14 days.'
      }
    ]
  end
  let(:crawl_result) do
    AiAgents::WebsiteCrawler::Result.new(
      pages: pages,
      source_urls: ['https://example.com/'],
      knowledge_content: "# Example policies\nSource: https://example.com/\nReturns are accepted within 14 days."
    )
  end

  before do
    allow(AiAgents::WebsiteCrawler).to receive(:new).with(source.website_url).and_return(crawler)
  end

  it 'stores readable website content and freshness metadata' do
    allow(crawler).to receive(:perform).and_return(crawl_result)

    described_class.perform_now(source.id)

    expect(source.reload).to have_attributes(
      sync_status: 'ready',
      source_urls: ['https://example.com/'],
      sync_error: nil
    )
    expect(source.content).to include('# Example policies', 'Source: https://example.com/', 'Returns are accepted within 14 days.')
    expect(source.last_synced_at).to be_present
  end

  it 'continues with the timestamp persisted by the database' do
    source
    precise_now = Time.at(1_800_000_000, Rational(123_456_789, 1_000)).utc
    allow(Time).to receive(:current).and_return(precise_now)
    allow(crawler).to receive(:perform).and_return(crawl_result)

    described_class.perform_now(source.id)

    expect(source.reload).to be_sync_ready
    expect(source.last_sync_started_at.nsec).to eq(123_456_000)
  end

  it 'updates freshness without changing updated_at when website content is unchanged' do
    compiled_content = "# Example policies\nSource: https://example.com/\nReturns are accepted within 14 days."
    source.update!(content: compiled_content, source_urls: ['https://example.com/'], sync_status: :pending, last_synced_at: 2.days.ago)
    assistant = create(:ai_agent, account: source.account)
    AiKnowledgeSources::AssignmentSync.new(assistant: assistant, source_ids: [source.id]).perform
    original_fingerprint = assistant.draft_fingerprint
    original_updated_at = source.updated_at
    allow(crawler).to receive(:perform).and_return(crawl_result)

    described_class.perform_now(source.id)

    expect(source.reload.updated_at).to eq(original_updated_at)
    expect(source).to have_attributes(sync_status: 'ready', content: compiled_content)
    expect(source.last_synced_at).to be > 1.day.ago
    expect(assistant.reload.draft_fingerprint).to eq(original_fingerprint)
  end

  it 'preserves last-known-good content when a resync fails' do
    source.update!(content: 'Previously verified policy', sync_status: :pending, last_synced_at: 1.day.ago)
    allow(crawler).to receive(:perform).and_raise(SafeFetch::FetchError, 'website unavailable')

    described_class.perform_now(source.id)

    expect(source.reload).to have_attributes(
      sync_status: 'failed',
      content: 'Previously verified policy',
      sync_error: 'website unavailable'
    )
  end

  it 'ignores stale jobs after the source leaves pending state' do
    source.update!(sync_status: :ready, content: 'Verified policy')

    expect(crawler).not_to receive(:perform)

    described_class.perform_now(source.id)
  end

  it 'does not let an old crawl overwrite a newly queued website URL' do
    allow(crawler).to receive(:perform) do
      source.reload.update!(website_url: 'https://example.com/new-policies', sync_status: :pending)
      crawl_result
    end

    described_class.perform_now(source.id)

    expect(source.reload).to have_attributes(
      website_url: 'https://example.com/new-policies',
      sync_status: 'pending',
      content: ''
    )
  end

  it 'does not let a timed-out worker overwrite a newer sync for the same URL' do
    allow(crawler).to receive(:perform) do
      source.update!(sync_status: :syncing, last_sync_started_at: 1.minute.from_now)
      crawl_result
    end

    described_class.perform_now(source.id)

    expect(source.reload).to have_attributes(sync_status: 'syncing', content: '')
  end

  it 'reclaims a website sync whose worker stopped updating it' do
    source.update!(sync_status: :syncing, last_sync_started_at: 20.minutes.ago)
    allow(crawler).to receive(:perform).and_return(crawl_result)

    described_class.perform_now(source.id)

    expect(crawler).to have_received(:perform).once
    expect(source.reload).to be_sync_ready
  end
end
