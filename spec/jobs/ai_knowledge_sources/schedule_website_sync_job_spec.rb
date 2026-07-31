require 'rails_helper'

RSpec.describe AiKnowledgeSources::ScheduleWebsiteSyncJob do
  let(:account) { create(:account) }

  def website_source(sync_status:, last_synced_at:)
    source = create(:ai_knowledge_source, account: account, source_type: 'website', website_url: 'https://example.com', content: 'Cached')
    # rubocop:disable Rails/SkipsModelValidations -- sync bookkeeping is deliberately set outside the model
    source.update_columns(sync_status: AiKnowledgeSource.sync_statuses.fetch(sync_status), last_synced_at: last_synced_at)
    # rubocop:enable Rails/SkipsModelValidations
    source
  end

  it 'queues a sync for website sources that have not been refreshed recently' do
    source = website_source(sync_status: 'ready', last_synced_at: 10.days.ago)

    expect { described_class.perform_now }.to have_enqueued_job(AiKnowledgeSources::WebsiteSyncJob).with(source.id)
    expect(source.reload).to be_sync_pending
  end

  it 'queues a sync for website sources that have never been synced' do
    source = website_source(sync_status: 'failed', last_synced_at: nil)

    expect { described_class.perform_now }.to have_enqueued_job(AiKnowledgeSources::WebsiteSyncJob).with(source.id)
  end

  it 'leaves recently synced sources alone' do
    source = website_source(sync_status: 'ready', last_synced_at: 1.day.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(AiKnowledgeSources::WebsiteSyncJob)
    expect(source.reload).to be_sync_ready
  end

  it 'does not disturb sources that are already queued or syncing' do
    pending_source = website_source(sync_status: 'pending', last_synced_at: 10.days.ago)
    syncing_source = website_source(sync_status: 'syncing', last_synced_at: 10.days.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(AiKnowledgeSources::WebsiteSyncJob)
    expect(pending_source.reload).to be_sync_pending
    expect(syncing_source.reload).to be_sync_syncing
  end

  it 'ignores manual sources' do
    create(:ai_knowledge_source, account: account, source_type: 'manual', content: 'Manual content')

    expect { described_class.perform_now }.not_to have_enqueued_job(AiKnowledgeSources::WebsiteSyncJob)
  end
end
