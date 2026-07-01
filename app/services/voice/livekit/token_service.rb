require 'jwt'

class Voice::Livekit::TokenService
  TOKEN_TTL = 6.hours

  def initialize(call:, identity:, name: nil)
    @call = call
    @identity = identity
    @name = name || identity
  end

  def payload
    {
      url: livekit_url,
      room: room_name,
      identity: identity,
      token: token
    }
  end

  private

  attr_reader :call, :identity, :name

  def token
    JWT.encode(claims, api_secret, 'HS256')
  end

  def claims
    now = Time.zone.now.to_i
    {
      iss: api_key,
      sub: identity,
      name: name,
      nbf: now,
      exp: (Time.zone.now + TOKEN_TTL).to_i,
      video: {
        room: room_name,
        roomJoin: true,
        canPublish: true,
        canSubscribe: true,
        canPublishData: true
      }
    }
  end

  def room_name
    call.livekit_room_name.presence || call.provider_call_id
  end

  def livekit_url
    ENV.fetch('LIVEKIT_URL')
  end

  def api_key
    ENV.fetch('LIVEKIT_API_KEY')
  end

  def api_secret
    ENV.fetch('LIVEKIT_API_SECRET')
  end
end
