# frozen_string_literal: true

# Website knowledge sources are only crawled when they are created, when their URL changes, or
# when an admin triggers a manual sync. Without a periodic refresh their content silently drifts
# away from the live website, so this job re-queues sources that have not been synced recently.
class AiKnowledgeSources::ScheduleWebsiteSyncJob < ApplicationJob
  class EnqueueError < StandardError; end

  STALE_AFTER = 7.days
  BATCH_SIZE = 100

  queue_as :scheduled_jobs

  def perform(stale_after: STALE_AFTER)
    stale_before = stale_after.ago
    due_sources(stale_before).find_each(batch_size: BATCH_SIZE) do |source|
      enqueue_sync(source, stale_before)
    end
  end

  private

  def due_sources(stale_before)
    AiKnowledgeSource
      .where(source_type: 'website')
      .where(sync_status: AiKnowledgeSource.sync_statuses.values_at('ready', 'failed'))
      .where(last_synced_at: [nil, ...stale_before])
  end

  def enqueue_sync(source, stale_before)
    previous_state = claim_source(source, stale_before)
    return unless previous_state

    enqueued_job = AiKnowledgeSources::WebsiteSyncJob.perform_later(source.id)
    return enqueued_job if enqueued_job

    raise EnqueueError, "Website sync could not be enqueued for source #{source.id}."
  rescue StandardError
    restore_source(source, previous_state) if previous_state
    raise
  end

  def claim_source(source, stale_before)
    source.with_lock do
      next unless due?(source, stale_before)

      previous_state = source.attributes.slice('sync_status', 'sync_error')
      source.update_columns( # rubocop:disable Rails/SkipsModelValidations -- queue state must not change the content fingerprint
        sync_status: AiKnowledgeSource.sync_statuses.fetch('pending'),
        sync_error: nil
      )
      previous_state
    end
  end

  def restore_source(source, previous_state)
    source.with_lock do
      next unless source.sync_pending?

      source.update_columns(previous_state) # rubocop:disable Rails/SkipsModelValidations -- restore a failed enqueue claim
    end
  end

  def due?(source, stale_before)
    source.website? &&
      (source.sync_ready? || source.sync_failed?) &&
      (source.last_synced_at.nil? || source.last_synced_at < stale_before)
  end
end
