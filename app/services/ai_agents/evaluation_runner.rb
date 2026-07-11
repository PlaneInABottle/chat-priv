# frozen_string_literal: true

class AiAgents::EvaluationRunner
  def initialize(run:)
    @run = run
  end

  def perform
    return unless run.pending?

    run.update!(status: :running, started_at: Time.current, error_message: nil)
    run.evaluation_results.order(:id).find_each { |result| evaluate(result) }
    complete_run
  rescue StandardError => e
    fail_run(e)
  end

  private

  attr_reader :run

  delegate :ai_agent, to: :run

  def evaluate(result)
    output = evaluation_output(result)
    assistant_response = assistant_response_from(output)
    raise StandardError, 'Assistant did not return a response' if assistant_response.blank?

    complete_result(result, output, assistant_response)
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
      improvement_operation: 'evaluation'
    ).perform
  end

  def assistant_response_from(output)
    output.dig(:assistant_message, 'content') || output.dig(:assistant_message, :content)
  end

  def complete_result(result, output, assistant_response)
    judgment = judge(result, output, assistant_response)
    result.update!(
      status: :completed,
      assistant_response: assistant_response,
      tool_events: output[:tool_events],
      passed: judgment.passed,
      reason: judgment.reason
    )
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
    result.update!(
      status: :failed,
      assistant_response: assistant_response,
      tool_events: output&.[](:tool_events) || [],
      passed: false,
      reason: "Evaluation could not complete: #{error.message}".truncate(500)
    )
  end

  def complete_run
    completed_results = run.evaluation_results.completed
    completed_count = completed_results.count
    passed_count = completed_results.where(passed: true).count
    run.update!(
      status: :completed,
      passed_count: passed_count,
      completed_at: Time.current
    )
    return unless run.total_count.positive? && completed_count == run.total_count && passed_count == run.total_count

    ai_agent.mark_test_succeeded!(prompt: run.prompt_snapshot, config: run.config_snapshot)
  end

  def fail_run(error)
    run.update!(status: :failed, completed_at: Time.current, error_message: error.message.truncate(500)) if run.persisted?
    Rails.logger.error("[AiAgents::EvaluationRunner] #{error.class}: #{error.message}")
  end
end
