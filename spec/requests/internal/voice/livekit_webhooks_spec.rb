require 'base64'
require 'digest'
require 'rails_helper'

RSpec.describe 'Internal LiveKit voice webhooks', type: :request do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) { create(:call, conversation: conversation, account: account, inbox: inbox, provider: :livekit, provider_call_id: 'room-1') }
  let!(:recording) do
    create(
      :voice_recording,
      account: account,
      call: call,
      status: 'active',
      egress_id: 'EG_test',
      bucket: 'voice-recordings-test',
      object_key: 'voice-recordings/account-1/call-1/room-1.mp4'
    )
  end

  it 'verifies the LiveKit webhook signature and marks egress completed' do
    payload = {
      event: 'egress_ended',
      egressInfo: {
        egressId: 'EG_test',
        status: 'EGRESS_COMPLETE',
        endedAt: 1_700_000_000_000_000_000,
        fileResults: [
          {
            duration: 12_000_000_000,
            location: 's3://voice-recordings-test/voice-recordings/account-1/call-1/room-1.mp4'
          }
        ]
      }
    }.to_json

    with_modified_env('LIVEKIT_API_KEY' => 'livekit-key', 'LIVEKIT_API_SECRET' => 'livekit-secret') do
      post '/internal/voice/livekit/webhook',
           params: payload,
           headers: {
             'CONTENT_TYPE' => 'application/webhook+json',
             'Authorization' => "Bearer #{webhook_token(payload)}"
           }
    end

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('status' => 'completed', 'recording_id' => recording.id)
    expect(recording.reload).to have_attributes(
      status: 'completed',
      duration_seconds: 12,
      object_key: 'voice-recordings/account-1/call-1/room-1.mp4'
    )
  end

  it 'rejects invalid signatures' do
    with_modified_env('LIVEKIT_API_KEY' => 'livekit-key', 'LIVEKIT_API_SECRET' => 'livekit-secret') do
      post '/internal/voice/livekit/webhook',
           params: { event: 'egress_ended' }.to_json,
           headers: {
             'CONTENT_TYPE' => 'application/webhook+json',
             'Authorization' => "Bearer #{JWT.encode({ iss: 'livekit-key', sha256: 'bad' }, 'livekit-secret', 'HS256')}"
           }
    end

    expect(response).to have_http_status(:unauthorized)
  end

  def webhook_token(raw_body)
    JWT.encode(
      {
        iss: 'livekit-key',
        sha256: Base64.strict_encode64(Digest::SHA256.digest(raw_body)),
        exp: 5.minutes.from_now.to_i,
        nbf: 1.minute.ago.to_i
      },
      'livekit-secret',
      'HS256'
    )
  end
end
