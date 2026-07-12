# frozen_string_literal: true

class AiAgents::EvaluationCaseGenerationJob < ApplicationJob
  USER_FACING_FAILURE = 'Suggested scenarios could not be prepared. Please try again.'
  CLAIM_TIMEOUT = 15.minutes

  queue_as :low

  def perform(generation)
    return unless claim(generation)

    scenarios = AiAgents::EvaluationCaseGenerator.new(
      ai_agent: generation.ai_agent,
      initiated_by: generation.initiated_by
    ).call(limit: generation.requested_count)
    created_count = create_cases(generation, scenarios)
    generation.update!(status: :completed, created_count: created_count, completed_at: Time.current)
  rescue StandardError => e
    fail_generation(generation, e)
  end

  private

  def claim(generation)
    generation.with_lock do
      next false unless generation.pending? || stale_running?(generation)

      generation.update!(status: :running, started_at: Time.current, completed_at: nil, error_message: nil)
      true
    end
  end

  def stale_running?(generation)
    generation.running? && generation.started_at.present? && generation.started_at < CLAIM_TIMEOUT.ago
  end

  def create_cases(generation, scenarios)
    ai_agent = generation.ai_agent
    ai_agent.with_lock do
      remaining_slots = AiAgentEvaluationCase::MAX_PER_ASSISTANT - ai_agent.evaluation_cases.count
      scenarios.first([remaining_slots, 0].max).count do |scenario|
        ai_agent.evaluation_cases.create!(
          scenario.merge(account: generation.account, position: next_position(ai_agent))
        )
      end
    end
  end

  def next_position(ai_agent)
    ai_agent.evaluation_cases.maximum(:position).to_i + 1
  end

  def fail_generation(generation, error)
    if generation&.persisted?
      generation.with_lock do
        if generation.pending? || generation.running?
          generation.update!(status: :failed, error_message: USER_FACING_FAILURE, completed_at: Time.current)
        end
      end
    end
    Rails.logger.error("[AiAgents::EvaluationCaseGenerationJob] #{error.class}: #{error.message}")
  end
end
