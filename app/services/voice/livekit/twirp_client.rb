require 'jwt'
require 'net/http'

class Voice::Livekit::TwirpClient
  OPEN_TIMEOUT = 3
  READ_TIMEOUT = 5
  TOKEN_TTL = 5.minutes

  def initialize(room_name:, subject:, video_grants: nil, api_key: nil, api_secret: nil)
    @room_name = room_name
    @subject = subject
    @video_grants = video_grants
    @api_key = api_key
    @api_secret = api_secret
  end

  def configured?
    [livekit_url, api_key, api_secret].all?(&:present?)
  end

  def post(service:, method:, body:)
    uri = URI("#{livekit_http_url}/twirp/livekit.#{service}/#{method}")
    request = Net::HTTP::Post.new(uri, headers)
    request.body = body.to_json

    Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == 'https',
      open_timeout: OPEN_TIMEOUT,
      read_timeout: READ_TIMEOUT
    ) do |http|
      http.request(request)
    end
  end

  def parse_json(body)
    JSON.parse(body.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  private

  attr_reader :room_name, :subject, :video_grants

  def headers
    {
      'Authorization' => "Bearer #{access_token}",
      'Content-Type' => 'application/json'
    }
  end

  def access_token
    now = Time.zone.now.to_i
    JWT.encode(
      {
        iss: api_key,
        sub: subject,
        nbf: now,
        exp: (Time.zone.now + TOKEN_TTL).to_i,
        video: resolved_video_grants
      },
      api_secret,
      'HS256'
    )
  end

  def resolved_video_grants
    return video_grants if video_grants.present?

    {
      room: room_name,
      roomAdmin: true
    }
  end

  def livekit_http_url
    livekit_url.sub(/\Awss:/, 'https:').sub(/\Aws:/, 'http:').delete_suffix('/')
  end

  def livekit_url
    ENV['LIVEKIT_URL'].to_s
  end

  def api_key
    @api_key.presence || ENV['LIVEKIT_API_KEY'].to_s
  end

  def api_secret
    @api_secret.presence || ENV['LIVEKIT_API_SECRET'].to_s
  end
end
