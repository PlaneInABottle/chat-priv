# frozen_string_literal: true

class AiAgents::WebsiteImportCreator
  COOLDOWN = 30.seconds
  DAILY_LIMIT = 10

  class RateLimited < StandardError
    attr_reader :retry_after

    def initialize(retry_after)
      @retry_after = retry_after
      super('Website analysis is temporarily unavailable. Please try again later.')
    end
  end

  def initialize(ai_agent:, website_url:, requested_by:)
    @ai_agent = ai_agent
    @website_url = website_url
    @requested_by = requested_by
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

  attr_reader :ai_agent, :website_url, :requested_by

  def create_import(normalized_url)
    ai_agent.account.with_lock do
      ai_agent.with_lock { create_locked_import(normalized_url) }
    end
  end

  def create_locked_import(normalized_url)
    active_import = ai_agent.website_imports.find_by(status: %i[pending running])
    return [active_import, false] if active_import && !stale?(active_import)

    expire_stale_import(active_import) if active_import

    reusable_import = reusable_ready_import(normalized_url)
    return [reusable_import, false] if reusable_import

    enforce_rate_limit!
    dismiss_ready_imports
    [persist_import(normalized_url), true]
  end

  def persist_import(normalized_url)
    ai_agent.website_imports.create!(
      account: ai_agent.account,
      requested_by: requested_by,
      website_url: normalized_url,
      status: :pending,
      stage: :queued,
      base_draft_fingerprint: ai_agent.draft_fingerprint,
      base_document: current_document
    )
  end

  def stale?(website_import)
    website_import.stale?
  end

  def expire_stale_import(website_import)
    website_import.update!(
      status: :failed,
      stage: :complete,
      base_document: nil,
      proposed_sections: {},
      proposed_knowledge_content: nil,
      error_code: 'stale_import',
      error_message: 'Website analysis did not finish. Start it again to retry.',
      completed_at: Time.current
    )
  end

  def reusable_ready_import(normalized_url)
    ai_agent.website_imports.ready.find_by(
      website_url: normalized_url,
      base_draft_fingerprint: ai_agent.draft_fingerprint,
      base_document: current_document
    )
  end

  def current_document
    instructions = ai_agent.config.to_h['instructions']
    return AiAgents::InstructionDocument.new(instructions).normalized if instructions.present?

    AiAgents::InstructionDocument.from_legacy(ai_agent.prompt)
  end

  def enforce_rate_limit!
    enforce_cooldown!
    enforce_daily_limit!
  end

  def enforce_cooldown!
    latest_import = ai_agent.account.ai_agent_website_imports.latest_first.first
    return unless latest_import&.created_at && latest_import.created_at > COOLDOWN.ago

    raise RateLimited, (latest_import.created_at + COOLDOWN - Time.current).ceil.clamp(1, COOLDOWN.to_i)
  end

  def enforce_daily_limit!
    recent_imports = ai_agent.account.ai_agent_website_imports.where(created_at: 1.day.ago..)
    return if recent_imports.count < DAILY_LIMIT

    oldest_import = recent_imports.order(:created_at).first
    raise RateLimited, (oldest_import.created_at + 1.day - Time.current).ceil.clamp(1, 1.day.to_i)
  end

  def dismiss_ready_imports
    ai_agent.website_imports.ready.find_each do |website_import|
      website_import.update!(
        status: :dismissed,
        stage: :complete,
        base_document: nil,
        proposed_sections: {},
        proposed_knowledge_content: nil,
        completed_at: Time.current
      )
    end
  end
end
