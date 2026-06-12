class Voice::Recordings::StartService
  def self.perform(call:)
    new(call: call).perform
  end

  def initialize(call:)
    @call = call
    @storage_config = Voice::Recordings::StorageConfig.new
  end

  def perform
    return skipped_result('not_livekit_call') unless call.livekit?
    return skipped_result('test_call') if call.test_call?
    return skipped_result('terminal_call') if call.terminal?
    return skipped_result('recording_disabled') unless recording_enabled?
    return skipped_result('recording_storage_not_configured') unless storage_config.configured?

    locked_result = reserve_recording
    return locked_result if locked_result.is_a?(Hash)

    recording = locked_result
    start_result = Voice::Livekit::EgressService.start_room_composite(call: call, recording: recording)
    apply_start_result(recording, start_result)
  end

  private

  attr_reader :call, :storage_config

  def recording_enabled?
    setting&.recording_enabled?
  end

  def setting
    @setting ||= call.account.voice_inbox_setting_for(
      inbox: call.inbox,
      id: call.meta&.fetch('voice_inbox_setting_id', nil)
    )
  end

  def build_recording
    VoiceRecording.create!(
      call: call,
      account: call.account,
      status: 'starting',
      storage_provider: storage_config.provider,
      bucket: storage_config.bucket,
      object_key: storage_config.object_key_for(call),
      content_type: storage_config.content_type,
      started_at: Time.zone.now
    )
  end

  def reserve_recording
    call.with_lock do
      if recordings_scope.active.exists?
        skipped_result('recording_already_started')
      elsif recordings_scope.completed.exists?
        skipped_result('recording_already_completed')
      else
        build_recording
      end
    end
  end

  def apply_start_result(recording, result)
    if result['status'] == 'ok' && result['egress_id'].present?
      recording.update!(
        status: 'active',
        egress_id: result['egress_id'],
        metadata: (recording.metadata || {}).merge('start_response' => result['response'])
      )
      Voice::CallMessageBuilder.new(call).update_status!(status: call.status)
      Voice::CallBroadcaster.safe_call_status_changed(call)
      return { 'status' => 'started', 'recording_id' => recording.id, 'egress_id' => recording.egress_id }
    end

    recording.update!(
      status: 'failed',
      error_message: result['error'] || result['reason'],
      metadata: (recording.metadata || {}).merge('start_result' => result)
    )
    { 'status' => 'failed', 'recording_id' => recording.id, 'error' => recording.error_message }
  end

  def skipped_result(reason)
    { 'status' => 'skipped', 'reason' => reason }
  end

  def recordings_scope
    VoiceRecording.where(call_id: call.id)
  end
end
