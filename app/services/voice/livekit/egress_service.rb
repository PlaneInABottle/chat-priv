class Voice::Livekit::EgressService
  def self.start_room_composite(call:, recording:)
    new(call: call, recording: recording).start_room_composite
  end

  def self.stop(egress_id:, call:)
    new(call: call, recording: nil).stop(egress_id)
  end

  def initialize(call:, recording:)
    @call = call
    @recording = recording
  end

  def start_room_composite
    return skipped_result unless client.configured?

    response = client.post(
      service: 'Egress',
      method: 'StartRoomCompositeEgress',
      body: start_body
    )
    parsed_body = client.parse_json(response.body)
    return success_result(parsed_body) if response.is_a?(Net::HTTPSuccess)

    failed_result(response.code, parsed_body['msg'] || parsed_body['error'] || response.body)
  rescue StandardError => e
    failed_result(nil, e.message, e.class.name)
  end

  def stop(egress_id)
    return skipped_result unless client.configured?

    response = client.post(service: 'Egress', method: 'StopEgress', body: { egress_id: egress_id })
    parsed_body = client.parse_json(response.body)
    return success_result(parsed_body) if response.is_a?(Net::HTTPSuccess)

    failed_result(response.code, parsed_body['msg'] || parsed_body['error'] || response.body)
  rescue StandardError => e
    failed_result(nil, e.message, e.class.name)
  end

  private

  attr_reader :call, :recording

  def start_body
    {
      room_name: room_name,
      audio_only: true,
      file_outputs: [
        {
          filepath: recording.object_key,
          s3: Voice::Recordings::StorageConfig.new.s3_upload
        }
      ]
    }
  end

  def client
    @client ||= Voice::Livekit::TwirpClient.new(
      room_name: room_name,
      subject: 'voice-recording-egress',
      video_grants: {
        room: room_name,
        roomRecord: true
      }
    )
  end

  def room_name
    call.livekit_room_name.presence || call.provider_call_id
  end

  def success_result(parsed_body)
    {
      'status' => 'ok',
      'egress_id' => parsed_body['egress_id'] || parsed_body['egressId'],
      'egress_status' => parsed_body['status'],
      'response' => parsed_body
    }.compact
  end

  def failed_result(code, message, error_class = nil)
    {
      'status' => 'failed',
      'code' => code,
      'error' => message.to_s.truncate(500),
      'error_class' => error_class
    }.compact
  end

  def skipped_result
    {
      'status' => 'skipped',
      'reason' => 'livekit_egress_not_configured'
    }
  end
end
