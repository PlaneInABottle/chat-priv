class Voice::Recordings::StopService
  def self.perform(call:)
    new(call: call).perform
  end

  def initialize(call:)
    @call = call
  end

  def perform
    recording = call.voice_recordings.active.latest_first.first
    return { 'status' => 'skipped', 'reason' => 'no_active_recording' } unless recording&.egress_id

    result = Voice::Livekit::EgressService.stop(egress_id: recording.egress_id, call: call)
    recording.update!(metadata: (recording.metadata || {}).merge('stop_result' => result))
    result
  end

  private

  attr_reader :call
end
