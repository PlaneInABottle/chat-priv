# frozen_string_literal: true

class AiKnowledgeSources::WebsiteSyncJob < ApplicationJob
  CLAIM_TIMEOUT = 15.minutes

  queue_as :low

  def perform(source_id)
    source = AiKnowledgeSource.find(source_id)
    sync_claim = start_sync(source)
    return unless sync_claim

    crawl_result = AiAgents::WebsiteCrawler.new(sync_claim[:url]).perform
    content = compiled_content(crawl_result.pages)
    raise AiAgents::WebsiteCrawler::InvalidWebsite, 'Website did not contain readable content.' if content.blank?

    complete_sync(source, content, crawl_result.source_urls, sync_claim)
  rescue StandardError => e
    fail_sync(source, e, sync_claim)
  end

  private

  def start_sync(source)
    source.with_lock do
      next false unless source.website? && (source.sync_pending? || stale_sync?(source))

      started_at = Time.current
      source.update_columns( # rubocop:disable Rails/SkipsModelValidations -- sync state must not change the content fingerprint
        sync_status: AiKnowledgeSource.sync_statuses.fetch('syncing'),
        last_sync_started_at: started_at,
        sync_error: nil
      )
      { url: source.website_url, started_at: source.reload.last_sync_started_at }
    end
  end

  def stale_sync?(source)
    source.sync_syncing? && source.last_sync_started_at.present? && source.last_sync_started_at < CLAIM_TIMEOUT.ago
  end

  def compiled_content(pages)
    Array(pages).filter_map do |page|
      text = page[:text].to_s.strip
      next if text.blank?

      title = page[:title].to_s.strip.presence || page[:url]
      "# #{title}\nSource: #{page[:url]}\n#{text}"
    end.join("\n\n")
  end

  def complete_sync(source, content, source_urls, sync_claim)
    attributes = {
      content: content,
      source_urls: source_urls,
      sync_status: :ready,
      sync_error: nil,
      last_synced_at: Time.current
    }
    source.with_lock do
      next unless current_sync?(source, sync_claim)
      next source.update!(attributes) if content_changed?(source, content, source_urls)

      source.update_columns( # rubocop:disable Rails/SkipsModelValidations -- unchanged content must preserve the content fingerprint
        sync_status: AiKnowledgeSource.sync_statuses.fetch('ready'),
        sync_error: nil,
        last_synced_at: attributes[:last_synced_at]
      )
    end
  end

  def content_changed?(source, content, source_urls)
    source.content != content || source.source_urls != source_urls
  end

  def fail_sync(source, error, sync_claim)
    return unless source&.persisted? && sync_claim

    source.with_lock do
      next unless current_sync?(source, sync_claim)

      source.update_columns( # rubocop:disable Rails/SkipsModelValidations -- failure metadata must preserve last-known-good content
        sync_status: AiKnowledgeSource.sync_statuses.fetch('failed'),
        sync_error: error.message.to_s.truncate(500)
      )
    end
    Rails.logger.error("[AiKnowledgeSources::WebsiteSyncJob] source=#{source.id} #{error.class}: #{error.message}")
  end

  def current_sync?(source, sync_claim)
    source.website? && source.sync_syncing? && source.website_url == sync_claim[:url] &&
      source.last_sync_started_at == sync_claim[:started_at]
  end
end
