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
    return call unless mark_terminal!

    consume_test_improvement_credit
    recording_result = stop_recording
    terminate_livekit_room
    persist_finalization_meta(recording_result)
    generate_summary
    Voice::ConversationHandoffState.clear_if_current!(call)
    Voice::CallMessageBuilder.new(call).update_status!(
      status: call.status,
      agent: agent || call.accepted_by_agent,
      duration_seconds: call.duration_seconds
    )
    Voice::CallBroadcaster.safe_call_status_changed(call)
    call
  end

  private

  attr_reader :call, :status, :end_reason, :ended_at, :duration_seconds, :agent

  def mark_terminal!
    finalized = false
    call.with_lock do
      next if call.terminal?

      call.update!(
        status: terminal_status,
        ended_at: ended_at.to_i,
        duration_seconds: resolved_duration_seconds,
        end_reason: end_reason
      )
      finalized = true
    end
    finalized
  end

  def terminal_status
    Call::TERMINAL_STATUSES.include?(status.to_s) ? status.to_s : 'completed'
  end

  def resolved_duration_seconds
    return duration_seconds if duration_seconds.present?
    return unless call.started_at

    (ended_at - call.started_at).to_i
  end

  def consume_test_improvement_credit
    return unless call.test_call?

    event = test_improvement_usage_event
    return unless event

    limiter = AiImprovements::Usage::Limiter.new(account: call.account, operation: event.operation)
    improvement_started_at = test_improvement_started_at
    return limiter.release!(event) unless improvement_started_at

    limiter.consume!(
      event,
      unit_type: 'audio_seconds',
      units: test_improvement_duration_seconds(improvement_started_at),
      metadata: { 'end_reason' => call.end_reason }
    )
  rescue StandardError => e
    Rails.logger.warn("voice test credit recording failed call_id=#{call.id} error=#{e.class.name}: #{e.message}")
  end

  def test_improvement_usage_event
    event_id = call.meta&.fetch('ai_improvement_usage_event_id', nil)
    call.account.ai_improvement_usage_events.find_by(id: event_id, call_id: call.id)
  end

  def test_improvement_started_at
    Time.zone.parse(call.meta.to_h['ai_improvement_started_at'].to_s)
  rescue ArgumentError
    nil
  end

  def test_improvement_duration_seconds(improvement_started_at)
    elapsed_seconds = [ended_at - improvement_started_at, 0].max
    duration_limit = call.meta.to_h['ai_improvement_max_duration_seconds'].to_i
    return elapsed_seconds unless duration_limit.positive?

    [elapsed_seconds, duration_limit].min
  end

  def stop_recording
    Voice::Recordings::StopService.perform(call: call)
  rescue StandardError => e
    Rails.logger.warn("voice recording stop failed call_id=#{call.id} error=#{e.class.name}: #{e.message}")
    {
      'status' => 'failed',
      'error' => e.message.to_s.truncate(500),
      'error_class' => e.class.name
    }
  end

  def persist_finalization_meta(recording_result)
    call.update!(
      meta: (call.meta || {}).merge(
        'finalized_by' => agent ? 'agent' : 'system',
        'finalized_at' => Time.zone.now.iso8601(3),
        'recording_stop' => recording_result
      ).compact
    )
  end

  def generate_summary
    Voice::CallSummaryGenerator.perform(call: call)
  end

  def terminate_livekit_room
    return unless call.livekit?

    customer_removal_result = Voice::Livekit::RoomService.remove_customer_participants(call: call)
    room_result = Voice::Livekit::RoomService.delete_room(call: call)
    local_hangup_result = Voice::Telephony::LocalAsteriskHangupService.perform(call: call)
    livekit_cleanup_meta = {
      'livekit_customer_removal' => customer_removal_result,
      'livekit_room_delete' => room_result
    }
    livekit_cleanup_meta['local_asterisk_hangup'] = local_hangup_result unless local_hangup_result['status'] == 'skipped'

    call.update!(
      meta: (call.meta || {}).merge(livekit_cleanup_meta)
    )
  rescue StandardError => e
    Rails.logger.warn("livekit room delete failed call_id=#{call.id} error=#{e.class.name}: #{e.message}")
  end
end
