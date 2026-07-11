# frozen_string_literal: true

class AiAgents::WebsiteImportJob < ApplicationJob
  queue_as :low

  def perform(website_import_id)
    website_import = AiAgentWebsiteImport.find(website_import_id)
    return unless start_import(website_import)

    crawl_result = AiAgents::WebsiteCrawler.new(website_import.website_url).perform
    website_import.update!(source_urls: crawl_result.source_urls, stage: :generating)
    generated = AiAgents::WebsiteInstructionGenerator.new(ai_agent: website_import.ai_agent).call(
      pages: crawl_result.pages,
      onboarding_answers: onboarding_answers(website_import.ai_agent)
    )
    website_import.update!(
      status: :ready,
      stage: :complete,
      proposed_sections: generated.sections,
      completed_at: Time.current
    )
    apply_initial_import(website_import)
  rescue StandardError => e
    fail_import(website_import, e)
  end

  private

  def start_import(website_import)
    website_import.with_lock do
      next false unless website_import.pending?

      website_import.update!(status: :running, stage: :crawling, started_at: Time.current, error_code: nil, error_message: nil)
    end
    true
  end

  def onboarding_answers(ai_agent)
    setup_profile = ai_agent.config.to_h.deep_stringify_keys['setup_profile'].to_h
    account_attributes = ai_agent.account.custom_attributes.to_h.slice('website', 'industry', 'company_size', 'user_role')
    setup_profile.merge(account_attributes)
  end

  def apply_initial_import(website_import)
    return unless website_import.mode_initial?
    return unless website_import.ai_agent.draft_fingerprint == website_import.base_draft_fingerprint

    website_import.update!(stage: :applying)
    AiAgents::WebsiteImportApplier.new(
      website_import: website_import,
      section_keys: website_import.proposed_sections.keys,
      expected_draft_fingerprint: website_import.base_draft_fingerprint
    ).perform
  rescue AiAgents::WebsiteImportApplier::Conflict
    nil
  end

  def fail_import(website_import, error)
    return unless website_import&.persisted?
    return if website_import.applied? || website_import.dismissed?

    website_import.update!(
      status: :failed,
      stage: :complete,
      error_code: error.class.name,
      error_message: error.message.to_s.truncate(500),
      completed_at: Time.current
    )
    Rails.logger.error("[AiAgents::WebsiteImportJob] import=#{website_import.id} #{error.class}: #{error.message}")
  end
end
