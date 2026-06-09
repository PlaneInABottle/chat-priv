class Voice::CallFinalizer
  def self.perform!(call:, status: 'completed', end_reason: nil, agent: nil, timing: {})
    new(call: call, status: status, end_reason: end_reason, agent: agent, timing: timing).perform!
  end

  def initialize(call:, status:, end_reason:, agent:, timing:)
    @call = call
    @status = status
    @end_reason = end_reason
    @agent = agent
    @ended_at = timing[:ended_at] || Time.zone.now
    @duration_seconds = timing[:duration_seconds]
  end

  def perform!
    return call if call.terminal?

    call.update!(
      status: terminal_status,
      ended_at: ended_at.to_i,
      duration_seconds: resolved_duration_seconds,
      end_reason: end_reason
    )
    Voice::CallMessageBuilder.new(call).update_status!(
      status: call.status,
      agent: agent || call.accepted_by_agent,
      duration_seconds: call.duration_seconds
    )
    Voice::CallBroadcaster.call_status_changed(call)
    call
  end

  private

  attr_reader :call, :status, :end_reason, :ended_at, :duration_seconds, :agent

  def terminal_status
    Call::TERMINAL_STATUSES.include?(status.to_s) ? status.to_s : 'completed'
  end

  def resolved_duration_seconds
    return duration_seconds if duration_seconds.present?
    return unless call.started_at

    (ended_at - call.started_at).to_i
  end
end
