class Voice::Livekit::AgentDispatchService
  def self.perform(call:, metadata: {})
    new(call: call, metadata: metadata).perform
  end

  def initialize(call:, metadata: {})
    @call = call
    @metadata = metadata
  end

  def perform
    return skipped_result unless configured?

    response = post_dispatch
    parsed_body = parse_json(response.body)
    return success_result(parsed_body) if response.is_a?(Net::HTTPSuccess)

    failed_result(response.code, parsed_body['msg'] || parsed_body['error'] || response.body)
  rescue StandardError => e
    failed_result(nil, e.message, e.class.name)
  end

  private

  attr_reader :call, :metadata

  def post_dispatch
    client.post(
      service: 'AgentDispatchService',
      method: 'CreateDispatch',
      body: {
        agent_name: agent_name,
        room: room_name,
        metadata: metadata.to_json
      }
    )
  end

  def client
    @client ||= Voice::Livekit::TwirpClient.new(room_name: room_name, subject: 'voice-agent-dispatch')
  end

  def configured?
    client.configured? && agent_name.present?
  end

  def skipped_result
    {
      'status' => 'skipped',
      'reason' => 'livekit_dispatch_not_configured'
    }
  end

  def success_result(parsed_body)
    {
      'status' => 'dispatched',
      'dispatch_id' => parsed_body['id'],
      'agent_name' => parsed_body['agent_name'] || parsed_body['agentName'] || agent_name,
      'room' => parsed_body['room'] || room_name
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

  def parse_json(body)
    client.parse_json(body)
  end

  def room_name
    call.livekit_room_name.presence || call.provider_call_id
  end

  def agent_name
    ENV.fetch('VOICE_AGENT_NAME', 'kozmopath-voice-agent')
  end
end
