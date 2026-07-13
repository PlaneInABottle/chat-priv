# frozen_string_literal: true

class AiAgents::EvaluationRunner
  ClaimLost = Class.new(StandardError)
  CLAIM_TIMEOUT = 15.minutes

  def initialize(run:)
    @run = run
  end

  def perform
    @claim_id = claim_run
    return unless claim_id

    run.evaluation_results.pending.order(:id).find_each { |result| evaluate(result) }
    complete_run
  rescue ClaimLost
    nil
  rescue StandardError => e
    fail_run(e)
  end

  private

  attr_reader :run, :claim_id

  delegate :ai_agent, to: :run

  def claim_run
    run.with_lock do
      next false unless run.pending? || stale_running_run?

      new_claim_id = SecureRandom.uuid
      run.update!(
        status: :running,
        claim_id: new_claim_id,
        started_at: Time.current,
        completed_at: nil,
        error_message: nil
      )
      new_claim_id
    end
  end

  def stale_running_run?
    run.running? && run.started_at.present? && run.started_at < CLAIM_TIMEOUT.ago
  end

  def heartbeat_claim!
    run.with_lock do
      raise ClaimLost unless current_claim?

      run.update!(started_at: Time.current)
    end
  end

  def current_claim?
    run.running? && run.claim_id == claim_id
  end

  def evaluate(result)
    heartbeat_claim!
    output = evaluation_output(result)
    heartbeat_claim!
    assistant_response = assistant_response_from(output)
    raise StandardError, 'Assistant did not return a response' if assistant_response.blank?

    judgment = judge(result, output, assistant_response)
    complete_result(result, output, assistant_response, judgment)
  rescue ClaimLost
    raise
  rescue StandardError => e
    fail_result(result, output, assistant_response, e)
  end

  def evaluation_output(result)
    AiAgents::Orchestrator.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: result.customer_message }],
      mode: :test,
      prompt_override: run.prompt_snapshot,
      config_override: run.config_snapshot,
      knowledge_sources_override: run.knowledge_snapshot,
      improvement_operation: 'evaluation'
    ).perform
  end

  def assistant_response_from(output)
    output.dig(:assistant_message, 'content') || output.dig(:assistant_message, :content)
  end

  def complete_result(result, output, assistant_response, judgment)
    run.with_lock do
      raise ClaimLost unless current_claim?

      result.with_lock do
        next unless result.pending?

        result.update!(
          status: :completed,
          assistant_response: assistant_response,
          tool_events: output[:tool_events],
          passed: judgment.passed,
          reason: judgment.reason
        )
      end
    end
  end

  def judge(result, output, assistant_response)
    AiAgents::EvaluationJudge.new(ai_agent: ai_agent).call(
      customer_message: result.customer_message,
      success_criteria: result.success_criteria,
      assistant_response: assistant_response,
      tool_events: output[:tool_events]
    )
  end

  def fail_result(result, output, assistant_response, error)
    run.with_lock do
      raise ClaimLost unless current_claim?

      result.with_lock do
        next unless result.pending?

        result.update!(
          status: :failed,
          assistant_response: assistant_response,
          tool_events: output&.[](:tool_events) || [],
          passed: false,
          reason: "Evaluation could not complete: #{error.message}".truncate(500)
        )
      end
    end
  end

  def complete_run
    all_passed = run.with_lock do
      raise ClaimLost unless current_claim?

      completed_results = run.evaluation_results.completed
      completed_count = completed_results.count
      passed_count = completed_results.where(passed: true).count
      run.update!(
        status: :completed,
        claim_id: nil,
        passed_count: passed_count,
        completed_at: Time.current
      )
      run.total_count.positive? && completed_count == run.total_count && passed_count == run.total_count
    end
    return unless all_passed

    ai_agent.mark_test_succeeded!(tested_fingerprint: run.draft_fingerprint)
  end

  def fail_run(error)
    if run.persisted? && claim_id
      run.with_lock do
        next unless current_claim?

        run.update!(
          status: :failed,
          claim_id: nil,
          completed_at: Time.current,
          error_message: error.message.truncate(500)
        )
      end
    end
    Rails.logger.error("[AiAgents::EvaluationRunner] #{error.class}: #{error.message}")
  end
end
