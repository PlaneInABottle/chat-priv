# frozen_string_literal: true

class AiAgents::WebsiteImportCreator
  STALE_AFTER = 5.minutes

  def initialize(ai_agent:, website_url:, requested_by:, mode: :preview)
    @ai_agent = ai_agent
    @website_url = website_url
    @requested_by = requested_by
    @mode = mode
  end

  def perform
    normalized_url = AiAgents::WebsiteCrawler.normalize_url(website_url)
    website_import, created = create_import(normalized_url)
    AiAgents::WebsiteImportJob.perform_later(website_import.id) if created
    website_import
  rescue ActiveRecord::RecordNotUnique
    ai_agent.website_imports.find_by!(status: %i[pending running])
  end

  private

  attr_reader :ai_agent, :website_url, :requested_by, :mode

  def create_import(normalized_url)
    ai_agent.with_lock do
      active_import = ai_agent.website_imports.find_by(status: %i[pending running])
      next [active_import, false] if active_import && !stale?(active_import)

      expire_stale_import(active_import) if active_import

      dismiss_ready_imports
      website_import = ai_agent.website_imports.create!(
        account: ai_agent.account,
        requested_by: requested_by,
        website_url: normalized_url,
        mode: mode,
        status: :pending,
        stage: :queued,
        base_draft_fingerprint: ai_agent.draft_fingerprint
      )
      [website_import, true]
    end
  end

  def stale?(website_import)
    website_import.updated_at < STALE_AFTER.ago
  end

  def expire_stale_import(website_import)
    website_import.update!(
      status: :failed,
      stage: :complete,
      error_code: 'stale_import',
      error_message: 'Website analysis did not finish. Start it again to retry.',
      completed_at: Time.current
    )
  end

  def dismiss_ready_imports
    ai_agent.website_imports.ready.find_each do |website_import|
      website_import.update!(status: :dismissed, stage: :complete, proposed_sections: {}, completed_at: Time.current)
    end
  end
end
