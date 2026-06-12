class Voice::Recordings::StopService
  def self.perform(call:)
    new(call: call).perform
  end

  def initialize(call:)
    @call = call
  end

  def perform
    recording = VoiceRecording.where(call_id: call.id).active.latest_first.first
    return { 'status' => 'skipped', 'reason' => 'no_active_recording' } unless recording&.egress_id

    result = Voice::Livekit::EgressService.stop(egress_id: recording.egress_id, call: call)
    recording.update!(metadata: (recording.metadata || {}).merge('stop_result' => result))
    finalize_from_stop_response(recording, result)
    result
  end

  private

  attr_reader :call

  def finalize_from_stop_response(recording, result)
    response = result['response']
    return unless result['status'] == 'ok' && response.is_a?(Hash)
    return unless response['status'].to_s == 'EGRESS_COMPLETE'

    Voice::Recordings::WebhookHandler.perform!(
      payload: {
        'event' => 'egress_ended',
        'egressInfo' => response
      }
    )
  end
end
