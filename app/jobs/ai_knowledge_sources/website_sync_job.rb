# frozen_string_literal: true

class AiKnowledgeSources::WebsiteSyncJob < ApplicationJob
  queue_as :low

  def perform(source_id)
    source = AiKnowledgeSource.find(source_id)
    sync_url = start_sync(source)
    return unless sync_url

    crawl_result = AiAgents::WebsiteCrawler.new(sync_url).perform
    content = compiled_content(crawl_result.pages)
    raise AiAgents::WebsiteCrawler::InvalidWebsite, 'Website did not contain readable content.' if content.blank?

    complete_sync(source, content, crawl_result.source_urls, sync_url)
  rescue StandardError => e
    fail_sync(source, e, sync_url)
  end

  private

  def start_sync(source)
    source.with_lock do
      next false unless source.website? && source.sync_pending?

      source.update_columns( # rubocop:disable Rails/SkipsModelValidations -- sync state must not change the content fingerprint
        sync_status: AiKnowledgeSource.sync_statuses.fetch('syncing'),
        last_sync_started_at: Time.current,
        sync_error: nil
      )
      source.website_url
    end
  end

  def compiled_content(pages)
    Array(pages).filter_map do |page|
      text = page[:text].to_s.strip
      next if text.blank?

      title = page[:title].to_s.strip.presence || page[:url]
      "# #{title}\nSource: #{page[:url]}\n#{text}"
    end.join("\n\n")
  end

  def complete_sync(source, content, source_urls, sync_url)
    attributes = {
      content: content,
      source_urls: source_urls,
      sync_status: :ready,
      sync_error: nil,
      last_synced_at: Time.current
    }
    source.with_lock do
      next unless current_sync?(source, sync_url)
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

  def fail_sync(source, error, sync_url)
    return unless source&.persisted? && sync_url

    source.with_lock do
      next unless current_sync?(source, sync_url)

      source.update_columns( # rubocop:disable Rails/SkipsModelValidations -- failure metadata must preserve last-known-good content
        sync_status: AiKnowledgeSource.sync_statuses.fetch('failed'),
        sync_error: error.message.to_s.truncate(500)
      )
    end
    Rails.logger.error("[AiKnowledgeSources::WebsiteSyncJob] source=#{source.id} #{error.class}: #{error.message}")
  end

  def current_sync?(source, sync_url)
    source.website? && source.sync_syncing? && source.website_url == sync_url
  end
end
