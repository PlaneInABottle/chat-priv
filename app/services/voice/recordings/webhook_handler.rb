class Voice::Recordings::WebhookHandler
  def self.perform!(payload:)
    new(payload: payload).perform!
  end

  def initialize(payload:)
    @payload = payload || {}
  end

  def perform!
    return { 'status' => 'ignored', 'reason' => 'not_egress_event' } unless egress_event?

    recording = find_recording
    return { 'status' => 'ignored', 'reason' => 'recording_not_found' } unless recording

    case event_name
    when 'egress_started', 'egress_updated'
      mark_active(recording)
    when 'egress_ended'
      mark_ended(recording)
    end
  end

  private

  attr_reader :payload

  def egress_event?
    event_name.in?(%w[egress_started egress_updated egress_ended]) && egress_info.present?
  end

  def find_recording
    return if egress_id.blank?

    VoiceRecording.find_by(egress_id: egress_id)
  end

  def mark_active(recording)
    return terminal_result(recording) if recording.terminal?

    recording.update!(
      status: 'active',
      metadata: (recording.metadata || {}).merge(event_name => egress_info)
    )
    { 'status' => 'updated', 'recording_id' => recording.id }
  end

  def mark_ended(recording)
    return terminal_result(recording) if recording.terminal?

    recording.transaction do
      attrs = ended_successfully? ? completed_attributes(recording) : failed_attributes
      recording.update!(attrs.merge(metadata: (recording.metadata || {}).merge(event_name => egress_info)))
      Voice::CallMessageBuilder.new(recording.call).update_status!(status: recording.call.status)
    end
    Voice::CallBroadcaster.safe_call_status_changed(recording.call)
    { 'status' => recording.status, 'recording_id' => recording.id }
  end

  def terminal_result(recording)
    { 'status' => recording.status, 'recording_id' => recording.id, 'reason' => 'already_terminal' }
  end

  def completed_attributes(recording)
    object_key = file_object_key(recording).presence || egress_file_path.presence || recording.object_key
    {
      status: 'completed',
      completed_at: ended_at,
      duration_seconds: duration_seconds,
      object_key: object_key,
      content_type: Voice::Recordings::StorageConfig.new.content_type_for(object_key),
      error_message: nil
    }.compact
  end

  def failed_attributes
    {
      status: 'failed',
      completed_at: ended_at,
      duration_seconds: duration_seconds,
      error_message: egress_info['error'].presence || egress_info['details'].presence || egress_status
    }.compact
  end

  def event_name
    payload['event']
  end

  def egress_info
    payload['egressInfo'] || payload['egress_info'] || {}
  end

  def egress_id
    egress_info['egressId'] || egress_info['egress_id']
  end

  def egress_status
    egress_info['status'].to_s
  end

  def ended_successfully?
    egress_status.blank? || egress_status == 'EGRESS_COMPLETE' || egress_status == '3'
  end

  def file_result
    egress_info['file'] || Array(egress_info['fileResults'] || egress_info['file_results']).first || {}
  end

  def egress_file_path
    request = egress_info['request'] || {}
    file_outputs = request['fileOutputs'] || request['file_outputs'] || []
    Array(file_outputs).first&.fetch('filepath', nil)
  end

  def file_object_key(recording)
    location = file_result['location'].to_s
    return if location.blank?

    path = URI.parse(location).path.delete_prefix('/')
    path.delete_prefix("#{recording.bucket}/")
  rescue URI::InvalidURIError
    nil
  end

  def ended_at
    ns_to_time(egress_info['endedAt'] || egress_info['ended_at']) || Time.zone.now
  end

  def duration_seconds
    duration = file_result['duration']
    return unless duration

    (duration.to_f / 1_000_000_000).round
  end

  def ns_to_time(value)
    return if value.blank?

    Time.zone.at(value.to_f / 1_000_000_000)
  end
end
