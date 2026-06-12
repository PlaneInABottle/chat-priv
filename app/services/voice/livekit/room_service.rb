class Voice::Livekit::RoomService
  AGENT_KIND_VALUES = ['AGENT', 'PARTICIPANT_KIND_AGENT', 4, '4'].freeze
  RoomRef = Struct.new(:livekit_room_name, :provider_call_id, keyword_init: true)

  def self.remove_agent_participants(call:)
    new(call: call).remove_agent_participants
  end

  def self.participant_summary(call:)
    new(call: call).participant_summary
  end

  def self.delete_room(call:)
    new(call: call).delete_room
  end

  def self.delete_room_name(room_name:)
    new(call: RoomRef.new(livekit_room_name: room_name, provider_call_id: room_name)).delete_room
  end

  def initialize(call:)
    @call = call
  end

  def remove_agent_participants
    return skipped_result unless configured?

    agents = list_participants.select { |participant| agent_participant?(participant) }
    removed_identities = agents.filter_map { |participant| remove_participant(participant['identity']) }

    {
      'status' => removed_identities.any? ? 'removed' : 'not_found',
      'removed_identities' => removed_identities
    }
  rescue StandardError => e
    {
      'status' => 'failed',
      'error' => e.message.to_s.truncate(500),
      'error_class' => e.class.name
    }
  end

  def participant_summary
    return skipped_result unless configured?

    participants = list_participants
    customer_participants = participants.reject { |participant| agent_participant?(participant) }
    {
      'status' => 'active',
      'participant_count' => participants.size,
      'customer_participant_count' => customer_participants.size,
      'agent_participant_count' => participants.size - customer_participants.size,
      'participant_identities' => participants.filter_map { |participant| participant['identity'] }
    }
  rescue StandardError => e
    return not_found_result(e) if room_not_found?(e)

    {
      'status' => 'failed',
      'error' => e.message.to_s.truncate(500),
      'error_class' => e.class.name
    }
  end

  def delete_room
    return skipped_result unless configured?

    response = delete_client.post(
      service: 'RoomService',
      method: 'DeleteRoom',
      body: { room: room_name }
    )
    parsed = parse_json(response.body)
    raise "LiveKit DeleteRoom failed: #{parsed['msg'] || parsed['error'] || response.body}" unless response.is_a?(Net::HTTPSuccess)

    {
      'status' => 'deleted',
      'room' => room_name
    }
  rescue StandardError => e
    return not_found_result(e) if room_not_found?(e)

    {
      'status' => 'failed',
      'error' => e.message.to_s.truncate(500),
      'error_class' => e.class.name
    }
  end

  private

  attr_reader :call

  def list_participants
    response = client.post(
      service: 'RoomService',
      method: 'ListParticipants',
      body: { room: room_name }
    )
    parsed = parse_json(response.body)
    raise "LiveKit ListParticipants failed: #{parsed['msg'] || parsed['error'] || response.body}" unless response.is_a?(Net::HTTPSuccess)

    parsed['participants'] || []
  end

  def remove_participant(identity)
    return if identity.blank?

    response = client.post(
      service: 'RoomService',
      method: 'RemoveParticipant',
      body: { room: room_name, identity: identity }
    )
    parsed = parse_json(response.body)
    raise "LiveKit RemoveParticipant failed: #{parsed['msg'] || parsed['error'] || response.body}" unless response.is_a?(Net::HTTPSuccess)

    identity
  end

  def client
    @client ||= Voice::Livekit::TwirpClient.new(room_name: room_name, subject: 'voice-room-admin')
  end

  def delete_client
    @delete_client ||= Voice::Livekit::TwirpClient.new(
      room_name: room_name,
      subject: 'voice-room-delete',
      video_grants: {
        room: room_name,
        roomCreate: true
      }
    )
  end

  def agent_participant?(participant)
    AGENT_KIND_VALUES.include?(participant['kind']) || participant['identity'].to_s.start_with?('agent-')
  end

  def room_not_found?(error)
    error.message.match?(/not[_ ]found|room.*not.*exist|does not exist/i)
  end

  def not_found_result(error)
    {
      'status' => 'not_found',
      'error' => error.message.to_s.truncate(500),
      'error_class' => error.class.name
    }
  end

  def skipped_result
    {
      'status' => 'skipped',
      'reason' => 'livekit_room_service_not_configured'
    }
  end

  def parse_json(body)
    client.parse_json(body)
  end

  def room_name
    call.livekit_room_name.presence || call.provider_call_id
  end

  def configured?
    client.configured?
  end
end
