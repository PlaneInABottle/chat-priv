require 'base64'
require 'digest'
require 'jwt'

class Voice::Livekit::WebhookVerifier
  def self.verify!(raw_body:, authorization_header:)
    new(raw_body: raw_body, authorization_header: authorization_header).verify!
  end

  def initialize(raw_body:, authorization_header:)
    @raw_body = raw_body.to_s
    @authorization_header = authorization_header.to_s
  end

  def verify!
    raise JWT::DecodeError, 'authorization header is empty' if token.blank?

    claims = JWT.decode(
      token,
      api_secret,
      true,
      {
        algorithm: 'HS256',
        iss: api_key,
        verify_iss: true
      }
    ).first
    raise JWT::DecodeError, 'sha256 checksum of body does not match' unless secure_hash_match?(claims['sha256'])

    JSON.parse(raw_body.presence || '{}')
  end

  private

  attr_reader :raw_body, :authorization_header

  def token
    authorization_header.delete_prefix('Bearer ').presence || authorization_header.presence
  end

  def secure_hash_match?(claim)
    return false if claim.blank?

    digest = Base64.strict_encode64(Digest::SHA256.digest(raw_body))
    ActiveSupport::SecurityUtils.secure_compare(digest, claim)
  end

  def api_key
    ENV.fetch('LIVEKIT_API_KEY')
  end

  def api_secret
    ENV.fetch('LIVEKIT_API_SECRET')
  end
end
