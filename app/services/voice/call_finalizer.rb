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
