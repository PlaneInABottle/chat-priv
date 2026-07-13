# frozen_string_literal: true

class AiAgents::LearningSuggestionJob < ApplicationJob
  CLAIM_TIMEOUT = 15.minutes

  queue_as :low

  def perform(suggestion)
    claim_id = claim(suggestion)
    return unless claim_id

    result = AiAgents::LearningSuggestionGenerator.new(
      ai_agent: suggestion.ai_agent,
      initiated_by: suggestion.submitted_by
    ).call(
      customer_message: suggestion.customer_message,
      human_answer: suggestion.human_answer
    )
    persist_result(suggestion, result, claim_id)
  rescue StandardError => e
    fail_suggestion(suggestion, e, claim_id)
  end

  private

  def claim(suggestion)
    suggestion.with_lock do
      next false unless suggestion.pending? || stale_analysis?(suggestion)

      claim_id = SecureRandom.uuid
      suggestion.update!(status: :analyzing, claim_id: claim_id, error_message: nil)
      claim_id
    end
  end

  def stale_analysis?(suggestion)
    suggestion.analyzing? && suggestion.updated_at < CLAIM_TIMEOUT.ago
  end

  def persist_result(suggestion, result, claim_id)
    suggestion.with_lock do
      next unless current_claim?(suggestion, claim_id)

      if result.useful
        suggestion.update!(
          status: :ready,
          claim_id: nil,
          destination: result.destination,
          target_section: result.target_section,
          source_name: result.source_name,
          suggested_instruction: result.instruction,
          reason: result.reason
        )
      else
        suggestion.update!(status: :not_recommended, claim_id: nil, reason: result.reason)
      end
    end
  end

  def fail_suggestion(suggestion, error, claim_id)
    if suggestion&.persisted? && claim_id
      suggestion.with_lock do
        next unless current_claim?(suggestion, claim_id)

        suggestion.update!(status: :failed, claim_id: nil, error_message: error.message.truncate(500))
      end
    end
    Rails.logger.error("[AiAgents::LearningSuggestionJob] #{error.class}: #{error.message}")
  end

  def current_claim?(suggestion, claim_id)
    suggestion.analyzing? && suggestion.claim_id == claim_id
  end
end
