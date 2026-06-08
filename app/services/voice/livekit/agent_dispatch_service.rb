require 'jwt'
require 'net/http'

class Voice::Livekit::AgentDispatchService
  ENDPOINT = '/twirp/livekit.AgentDispatchService/CreateDispatch'.freeze
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5
  TOKEN_TTL = 5.minutes

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
    request = Net::HTTP::Post.new(dispatch_uri, headers)
    request.body = {
      agent_name: agent_name,
      room: room_name,
      metadata: metadata.to_json
    }.to_json

    Net::HTTP.start(
      dispatch_uri.host,
      dispatch_uri.port,
      use_ssl: dispatch_uri.scheme == 'https',
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT
    ) do |http|
      http.request(request)
    end
  end

  def headers
    {
      'Authorization' => "Bearer #{admin_token}",
      'Content-Type' => 'application/json'
    }
  end

  def admin_token
    now = Time.zone.now.to_i
    JWT.encode(
      {
        iss: api_key,
        sub: 'voice-agent-dispatch',
        nbf: now,
        exp: (Time.zone.now + TOKEN_TTL).to_i,
        video: {
          room: room_name,
          roomAdmin: true
        }
      },
      api_secret,
      'HS256'
    )
  end

  def dispatch_uri
    @dispatch_uri ||= URI("#{livekit_http_url}#{ENDPOINT}")
  end

  def livekit_http_url
    livekit_url.sub(/\Awss:/, 'https:').sub(/\Aws:/, 'http:').delete_suffix('/')
  end

  def configured?
    [livekit_url, api_key, api_secret, agent_name].all?(&:present?)
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
      'agent_name' => parsed_body['agent_name'] || agent_name,
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
    JSON.parse(body.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def room_name
    call.livekit_room_name.presence || call.provider_call_id
  end

  def livekit_url
    ENV['LIVEKIT_URL'].to_s
  end

  def api_key
    ENV['LIVEKIT_API_KEY'].to_s
  end

  def api_secret
    ENV['LIVEKIT_API_SECRET'].to_s
  end

  def agent_name
    ENV.fetch('VOICE_AGENT_NAME', 'kozmopath-voice-agent')
  end
end
