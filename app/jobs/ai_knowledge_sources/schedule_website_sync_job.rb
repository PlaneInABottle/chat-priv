# frozen_string_literal: true

# Website knowledge sources are only crawled when they are created, when their URL changes, or
# when an admin triggers a manual sync. Without a periodic refresh their content silently drifts
# away from the live website, so this job re-queues sources that have not been synced recently.
class AiKnowledgeSources::ScheduleWebsiteSyncJob < ApplicationJob
  STALE_AFTER = 7.days
  BATCH_SIZE = 100

  queue_as :scheduled_jobs

  def perform(stale_after: STALE_AFTER)
    due_sources(stale_after).find_each(batch_size: BATCH_SIZE) do |source|
      enqueue_sync(source)
    end
  end

  private

  def due_sources(stale_after)
    AiKnowledgeSource
      .where(source_type: 'website')
      .where(sync_status: AiKnowledgeSource.sync_statuses.values_at('ready', 'failed'))
      .where(last_synced_at: [nil, ...stale_after.ago])
  end

  def enqueue_sync(source)
    source.update_columns( # rubocop:disable Rails/SkipsModelValidations -- queue state must not change the content fingerprint
      sync_status: AiKnowledgeSource.sync_statuses.fetch('pending'),
      sync_error: nil
    )
    AiKnowledgeSources::WebsiteSyncJob.perform_later(source.id)
  end
end
