class Voice::TestCallImprovementBudgetJob < ApplicationJob
  PARTICIPANT_JOIN_GRACE = 2.minutes

  queue_as :default

  def perform(call)
    call.reload
    return unless call.test_call? && !call.terminal?

    duration_limit = call.meta.to_h['ai_improvement_max_duration_seconds'].to_i
    return unless duration_limit.positive?

    improvement_started_at = parse_improvement_started_at(call)
    return finalize_unjoined_call(call) unless improvement_started_at

    deadline = improvement_started_at + duration_limit.seconds
    return reschedule(call, deadline) if deadline.future?

    Voice::CallFinalizer.perform!(
      call: call,
      end_reason: 'ai_improvement_credit_limit',
      timing: { ended_at: deadline, duration_seconds: duration_limit }
    )
  end

  private

  def parse_improvement_started_at(call)
    Time.zone.parse(call.meta.to_h['ai_improvement_started_at'].to_s)
  rescue ArgumentError
    nil
  end

  def finalize_unjoined_call(call)
    ended_at = call.started_at ? call.started_at + PARTICIPANT_JOIN_GRACE : Time.current
    Voice::CallFinalizer.perform!(
      call: call,
      status: 'no_answer',
      end_reason: 'participant_timeout',
      timing: { ended_at: ended_at, duration_seconds: 0 }
    )
  end

  def reschedule(call, deadline)
    self.class.set(wait: deadline - Time.current).perform_later(call)
  end
end
