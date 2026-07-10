# frozen_string_literal: true

class AiAgents::LearningSuggestionApplier
  class InvalidSuggestion < StandardError; end

  def initialize(suggestion:, reviewer:, instruction:, target_section:)
    @suggestion = suggestion
    @reviewer = reviewer
    @instruction = instruction.to_s.strip
    @target_section = target_section.to_s
  end

  def perform
    validate_review!

    AiAgentLearningSuggestion.transaction do
      suggestion.lock!
      raise InvalidSuggestion, 'Only ready suggestions can be applied.' unless suggestion.ready?

      ai_agent.lock!
      apply_to_draft!
      suggestion.update!(
        status: :applied,
        suggested_instruction: instruction,
        target_section: target_section,
        reviewed_by: reviewer,
        reviewed_at: Time.current,
        applied_at: Time.current
      )
    end

    suggestion
  end

  private

  attr_reader :suggestion, :reviewer, :instruction, :target_section

  delegate :ai_agent, to: :suggestion

  def validate_review!
    raise InvalidSuggestion, 'Instruction cannot be blank.' if instruction.blank?
    return if AiAgentLearningSuggestion::TARGET_SECTIONS.include?(target_section)

    raise InvalidSuggestion, 'Choose a valid instruction section.'
  end

  def apply_to_draft!
    document = current_instruction_document
    current_content = document.dig('sections', target_section).to_s.strip
    document['sections'][target_section] = [current_content, instruction].compact_blank.join("\n\n")

    updated_config = ai_agent.config.to_h.deep_stringify_keys.merge('instructions' => document)
    ai_agent.update!(
      config: updated_config,
      prompt: AiAgents::InstructionDocument.new(document).compile
    )
  end

  def current_instruction_document
    source = ai_agent.config.to_h.deep_stringify_keys['instructions']
    return AiAgents::InstructionDocument.new(source).normalized if source.present?

    AiAgents::InstructionDocument.from_legacy(ai_agent.prompt)
  end
end
