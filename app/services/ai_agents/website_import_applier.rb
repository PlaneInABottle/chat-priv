# frozen_string_literal: true

class AiAgents::WebsiteImportApplier
  class Conflict < StandardError; end
  class InvalidSelection < StandardError; end

  def initialize(website_import:, section_keys:, expected_draft_fingerprint:, required_mode: nil)
    @website_import = website_import
    @section_keys = Array(section_keys).map(&:to_s).uniq
    @expected_draft_fingerprint = expected_draft_fingerprint.to_s
    @required_mode = required_mode&.to_s
  end

  def perform
    website_import.with_lock do
      raise InvalidSelection, 'Website import is not ready to apply.' unless website_import.ready?
      raise Conflict, 'Website import mode changed before it could be applied.' unless required_mode_matches?

      ai_agent.with_lock do
        raise Conflict, 'Assistant instructions changed after this preview was opened.' unless fingerprint_matches?

        selected_sections = selected_proposals
        raise InvalidSelection, 'Select at least one proposed section.' if selected_sections.empty?

        website_import.update!(stage: :applying)
        update_agent(selected_sections)
        website_import.update!(
          status: :applied,
          stage: :complete,
          proposed_sections: {},
          applied_at: Time.current,
          completed_at: Time.current
        )
      end
    end
    ai_agent
  end

  private

  attr_reader :website_import, :section_keys, :expected_draft_fingerprint, :required_mode

  delegate :ai_agent, to: :website_import

  def fingerprint_matches?
    expected_draft_fingerprint.present? &&
      website_import.base_draft_fingerprint == expected_draft_fingerprint &&
      ai_agent.draft_fingerprint == expected_draft_fingerprint
  end

  def required_mode_matches?
    required_mode.blank? || website_import.mode == required_mode
  end

  def selected_proposals
    allowed_keys = section_keys & AiAgentWebsiteImport::APPLYABLE_SECTIONS
    proposals = website_import.proposed_sections.to_h.deep_stringify_keys
    allowed_keys.filter_map do |key|
      value = proposals[key].to_s.strip
      [key, value] if value.present?
    end.to_h
  end

  def update_agent(selected_sections)
    config = ai_agent.config.to_h.deep_stringify_keys
    document = AiAgents::InstructionDocument.new(config['instructions']).normalized
    document['sections'].merge!(selected_sections)
    config['instructions'] = document
    ai_agent.update!(config: config, prompt: AiAgents::InstructionDocument.new(document).compile)
  end
end
