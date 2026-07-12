# frozen_string_literal: true

class AiAgents::LearningSuggestionApplier
  class InvalidSuggestion < StandardError; end

  def initialize(suggestion:, reviewer:, review:)
    @suggestion = suggestion
    @reviewer = reviewer
    @instruction = review[:instruction].to_s.strip
    @destination = (review[:destination].presence || suggestion.destination).to_s
    @target_section = (review[:target_section].presence || suggestion.target_section).to_s
    @source_name = (review[:source_name].presence || suggestion.source_name).to_s.strip
  end

  def perform
    validate_review!

    AiAgentLearningSuggestion.transaction do
      suggestion.lock!
      raise InvalidSuggestion, 'Only ready suggestions can be applied.' unless suggestion.ready?

      ai_agent.lock!
      apply_improvement!
      suggestion.update!(
        status: :applied,
        suggested_instruction: instruction,
        destination: destination,
        target_section: destination == 'instructions' ? target_section : nil,
        source_name: destination == 'knowledge' ? source_name : nil,
        ai_knowledge_source: knowledge_source,
        reviewed_by: reviewer,
        reviewed_at: Time.current,
        applied_at: Time.current
      )
    end

    suggestion
  end

  private

  attr_reader :suggestion, :reviewer, :instruction, :destination, :target_section, :source_name, :knowledge_source

  delegate :ai_agent, to: :suggestion

  def validate_review!
    raise InvalidSuggestion, 'Instruction cannot be blank.' if instruction.blank?
    raise InvalidSuggestion, 'Choose where to save this learning.' unless AiAgentLearningSuggestion::DESTINATIONS.include?(destination)
    return validate_knowledge_review! if destination == 'knowledge'
    return if AiAgentLearningSuggestion::TARGET_SECTIONS.include?(target_section)

    raise InvalidSuggestion, 'Choose a valid instruction section.'
  end

  def validate_knowledge_review!
    raise InvalidSuggestion, 'Knowledge source name cannot be blank.' if source_name.blank?
    raise InvalidSuggestion, 'Knowledge source name is too long.' if source_name.length > 120
  end

  def apply_improvement!
    destination == 'knowledge' ? apply_to_knowledge! : apply_to_draft!
  end

  def apply_to_knowledge!
    @knowledge_source = suggestion.account.ai_knowledge_sources.create!(
      name: source_name,
      source_type: 'manual',
      content: instruction
    )
    AiKnowledgeSourceAssignment.create!(
      account: suggestion.account,
      assistant: ai_agent,
      ai_knowledge_source: knowledge_source
    )
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
