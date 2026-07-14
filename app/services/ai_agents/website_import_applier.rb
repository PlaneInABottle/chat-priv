# frozen_string_literal: true

class AiAgents::WebsiteImportApplier
  MAX_INSTRUCTION_LENGTH = 50_000

  class Conflict < StandardError; end

  class InvalidSelection < StandardError
    attr_reader :code

    def initialize(message, code: 'invalid_selection')
      @code = code
      super(message)
    end
  end

  def initialize(website_import:, section_keys:, expected_draft_fingerprint:, current_document: nil, attach_knowledge: false)
    @website_import = website_import
    @section_keys = Array(section_keys).map(&:to_s).uniq
    @expected_draft_fingerprint = expected_draft_fingerprint.to_s
    @current_document = current_document
    @attach_knowledge = ActiveModel::Type::Boolean.new.cast(attach_knowledge)
  end

  def perform
    ActiveRecord::Base.transaction do
      account.lock!
      ai_agent.lock!
      website_import.lock!
      validate_import!

      proposals = selected_proposals
      validate_selected_content!(proposals)
      document = normalized_current_document
      document['sections'].merge!(proposals)
      compiled_prompt = AiAgents::InstructionDocument.new(document).compile
      raise InvalidSelection, 'Assistant instructions are too long.' if compiled_prompt.length > MAX_INSTRUCTION_LENGTH

      knowledge_source = upsert_knowledge_source if attach_knowledge
      update_agent(document, compiled_prompt, knowledge_source)
      complete_import(knowledge_source)
    end
    ai_agent
  end

  private

  attr_reader :website_import, :section_keys, :expected_draft_fingerprint, :current_document, :attach_knowledge

  delegate :ai_agent, :account, to: :website_import

  def validate_import!
    raise InvalidSelection, 'Website import is not ready to apply.' unless website_import.ready?
    raise InvalidSelection, 'This website analysis must be run again before it can be reviewed.' if website_import.base_document.blank?
    raise Conflict, 'Assistant instructions changed after this preview was opened.' unless fingerprint_matches?
    raise InvalidSelection, 'Select at least one suggestion or add the website to Shared Knowledge.' if section_keys.empty? && !attach_knowledge
  end

  def fingerprint_matches?
    expected_draft_fingerprint.present? &&
      website_import.base_draft_fingerprint == expected_draft_fingerprint &&
      ai_agent.draft_fingerprint == expected_draft_fingerprint
  end

  def selected_proposals
    unknown_keys = section_keys - AiAgentWebsiteImport::APPLYABLE_SECTIONS
    raise InvalidSelection, 'Website import included an unsupported section.' if unknown_keys.any?

    proposals = website_import.proposed_sections.to_h.deep_stringify_keys
    section_keys.filter_map do |key|
      value = proposals[key].to_s.strip
      [key, value] if value.present?
    end.to_h
  end

  def validate_selected_content!(proposals)
    return if proposals.any? || attach_knowledge

    raise InvalidSelection, 'Select at least one available suggestion.'
  end

  def normalized_current_document
    source = current_document.presence || persisted_document
    AiAgents::InstructionDocument.new(source).normalized
  end

  def persisted_document
    instructions = ai_agent.config.to_h['instructions']
    return instructions if instructions.present?

    AiAgents::InstructionDocument.from_legacy(ai_agent.prompt)
  end

  def update_agent(document, compiled_prompt, knowledge_source)
    source_ids = knowledge_source ? ai_agent.knowledge_source_ids | [knowledge_source.id] : nil
    validate_knowledge_source_limit!(source_ids)

    config = ai_agent.config.to_h.deep_stringify_keys
    config['instructions'] = document
    ai_agent.update!(config: config, prompt: compiled_prompt)
    return unless knowledge_source

    AiKnowledgeSources::AssignmentSync.new(assistant: ai_agent, source_ids: source_ids).perform
  end

  def validate_knowledge_source_limit!(source_ids)
    return if source_ids.blank? || source_ids.length <= AiKnowledgeSources::AssignmentSync::MAX_SOURCES

    raise InvalidSelection.new(
      "An assistant can use up to #{AiKnowledgeSources::AssignmentSync::MAX_SOURCES} knowledge sources.",
      code: 'knowledge_source_limit'
    )
  end

  def upsert_knowledge_source
    content = website_import.proposed_knowledge_content.to_s.strip
    raise InvalidSelection, 'Website analysis did not produce reusable knowledge.' if content.blank?

    source = account.ai_knowledge_sources.find_or_initialize_by(
      source_type: 'website',
      website_url: website_import.website_url
    )
    source.assign_attributes(
      name: source.name.presence || knowledge_source_name,
      content: content,
      source_urls: website_import.source_urls,
      sync_status: :ready,
      sync_error: nil,
      last_synced_at: Time.current
    )
    source.save!
    source
  end

  def knowledge_source_name
    host = URI.parse(website_import.website_url).host.to_s.delete_prefix('www.')
    "#{host} website".truncate(120)
  end

  def complete_import(knowledge_source)
    website_import.update!(
      status: :applied,
      stage: :complete,
      ai_knowledge_source: knowledge_source,
      base_document: nil,
      proposed_sections: {},
      proposed_knowledge_content: nil,
      applied_at: Time.current,
      completed_at: Time.current
    )
  end
end
