# frozen_string_literal: true

class AiAgents::EvaluationCaseGenerationJob < ApplicationJob
  queue_as :low

  def perform(generation)
    claim_id = claim(generation)
    return unless claim_id

    scenarios = AiAgents::EvaluationCaseGenerator.new(
      ai_agent: generation.ai_agent,
      initiated_by: generation.initiated_by
    ).call(limit: generation.requested_count)
    complete_generation(generation, scenarios, claim_id)
  rescue StandardError => e
    fail_generation(generation, e, claim_id)
  end

  private

  def claim(generation)
    generation.with_lock do
      next false unless generation.pending? || stale_running?(generation)

      claim_id = SecureRandom.uuid
      generation.update!(
        status: :running,
        claim_id: claim_id,
        started_at: Time.current,
        completed_at: nil,
        error_message: nil
      )
      claim_id
    end
  end

  def stale_running?(generation)
    generation.running? && generation.started_at.present? && generation.started_at < AiAgentEvaluationGeneration::CLAIM_TIMEOUT.ago
  end

  def complete_generation(generation, scenarios, claim_id)
    generation.with_lock do
      next unless current_claim?(generation, claim_id)

      created_count = create_cases(generation, scenarios)
      generation.update!(
        status: :completed,
        claim_id: nil,
        created_count: created_count,
        completed_at: Time.current
      )
    end
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

  def fail_generation(generation, error, claim_id)
    if generation&.persisted? && claim_id
      generation.with_lock do
        next unless current_claim?(generation, claim_id)

        generation.update!(
          status: :failed,
          claim_id: nil,
          error_message: AiAgentEvaluationGeneration::USER_FACING_FAILURE,
          completed_at: Time.current
        )
      end
    end
    Rails.logger.error("[AiAgents::EvaluationCaseGenerationJob] #{error.class}: #{error.message}")
  end

  def current_claim?(generation, claim_id)
    generation.running? && generation.claim_id == claim_id
  end
end
