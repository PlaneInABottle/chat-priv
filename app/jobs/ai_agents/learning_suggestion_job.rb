# frozen_string_literal: true

class AiAgents::LearningSuggestionJob < ApplicationJob
  queue_as :low

  def perform(suggestion)
    return unless claim(suggestion)

    result = AiAgents::LearningSuggestionGenerator.new(ai_agent: suggestion.ai_agent).call(
      customer_message: suggestion.customer_message,
      human_answer: suggestion.human_answer
    )
    persist_result(suggestion, result)
  rescue StandardError => e
    fail_suggestion(suggestion, e)
  end

  private

  def claim(suggestion)
    suggestion.with_lock do
      next false unless suggestion.pending?

      suggestion.update!(status: :analyzing, error_message: nil)
      true
    end
  end

  def persist_result(suggestion, result)
    suggestion.with_lock do
      next unless suggestion.analyzing?

      if result.useful
        suggestion.update!(
          status: :ready,
          target_section: result.target_section,
          suggested_instruction: result.instruction,
          reason: result.reason
        )
      else
        suggestion.update!(status: :not_recommended, reason: result.reason)
      end
    end
  end

  def fail_suggestion(suggestion, error)
    if suggestion&.persisted?
      suggestion.with_lock do
        suggestion.update!(status: :failed, error_message: error.message.truncate(500)) if suggestion.analyzing?
      end
    end
    Rails.logger.error("[AiAgents::LearningSuggestionJob] #{error.class}: #{error.message}")
  end
end
