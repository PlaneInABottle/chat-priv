# frozen_string_literal: true

class AiAgents::WebsiteImportJob < ApplicationJob
  queue_as :low

  def perform(website_import_id)
    website_import = AiAgentWebsiteImport.find(website_import_id)
    claim_started_at = start_import(website_import)
    return unless claim_started_at

    crawl_result = AiAgents::WebsiteCrawler.new(website_import.website_url).perform
    return unless advance_to_generation(website_import, claim_started_at, crawl_result.source_urls)

    generated = generate_instructions(website_import, crawl_result)
    complete_import(website_import, claim_started_at, generated.sections, crawl_result.knowledge_content)
  rescue StandardError => e
    fail_import(website_import, e, claim_started_at)
  end

  private

  def generate_instructions(website_import, crawl_result)
    AiAgents::WebsiteInstructionGenerator.new(
      ai_agent: website_import.ai_agent,
      initiated_by: website_import.requested_by
    ).call(
      pages: crawl_result.pages,
      business_context: business_context(website_import.ai_agent)
    )
  end

  def start_import(website_import)
    website_import.with_lock do
      next false unless website_import.pending?

      started_at = Time.current
      website_import.update!(status: :running, stage: :crawling, started_at: started_at, error_code: nil, error_message: nil)
      website_import.reload.started_at
    end
  end

  def advance_to_generation(website_import, claim_started_at, source_urls)
    website_import.with_lock do
      next false unless current_claim?(website_import, claim_started_at)

      website_import.update!(source_urls: source_urls, stage: :generating)
      true
    end
  end

  def complete_import(website_import, claim_started_at, proposed_sections, proposed_knowledge_content)
    website_import.with_lock do
      next false unless current_claim?(website_import, claim_started_at)

      website_import.update!(
        status: :ready,
        stage: :complete,
        proposed_sections: proposed_sections,
        proposed_knowledge_content: proposed_knowledge_content,
        completed_at: Time.current
      )
      true
    end
  end

  def current_claim?(website_import, claim_started_at)
    website_import.running? && website_import.started_at == claim_started_at
  end

  def business_context(ai_agent)
    {
      company_name: ai_agent.account.name,
      industry: ai_agent.account.custom_attributes.to_h['industry'].presence
    }.compact
  end

  def fail_import(website_import, error, claim_started_at)
    return unless website_import&.persisted? && claim_started_at

    website_import.with_lock do
      next unless current_claim?(website_import, claim_started_at)

      website_import.update!(
        status: :failed,
        stage: :complete,
        base_document: nil,
        proposed_sections: {},
        proposed_knowledge_content: nil,
        error_code: error.class.name,
        error_message: error.message.to_s.truncate(500),
        completed_at: Time.current
      )
    end
    Rails.logger.error("[AiAgents::WebsiteImportJob] import=#{website_import.id} #{error.class}: #{error.message}")
  end
end
