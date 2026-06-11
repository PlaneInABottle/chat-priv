require 'base64'
require 'digest'
require 'rails_helper'

RSpec.describe Voice::Livekit::WebhookVerifier do
  let(:raw_body) { { event: 'egress_ended' }.to_json }

  it 'returns parsed payload when the LiveKit JWT hash matches the raw body' do
    payload = with_modified_env('LIVEKIT_API_KEY' => 'livekit-key', 'LIVEKIT_API_SECRET' => 'livekit-secret') do
      described_class.verify!(raw_body: raw_body, authorization_header: "Bearer #{token_for(raw_body)}")
    end

    expect(payload).to eq('event' => 'egress_ended')
  end

  it 'rejects a token signed for a different body' do
    expect do
      with_modified_env('LIVEKIT_API_KEY' => 'livekit-key', 'LIVEKIT_API_SECRET' => 'livekit-secret') do
        described_class.verify!(raw_body: raw_body, authorization_header: "Bearer #{token_for('different')}")
      end
    end.to raise_error(JWT::DecodeError, 'sha256 checksum of body does not match')
  end

  it 'rejects missing authorization' do
    expect do
      with_modified_env('LIVEKIT_API_KEY' => 'livekit-key', 'LIVEKIT_API_SECRET' => 'livekit-secret') do
        described_class.verify!(raw_body: raw_body, authorization_header: nil)
      end
    end.to raise_error(JWT::DecodeError, 'authorization header is empty')
  end

  def token_for(body)
    JWT.encode(
      {
        iss: 'livekit-key',
        sha256: Base64.strict_encode64(Digest::SHA256.digest(body)),
        exp: 5.minutes.from_now.to_i,
        nbf: 1.minute.ago.to_i
      },
      'livekit-secret',
      'HS256'
    )
  end
end
