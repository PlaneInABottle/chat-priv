require 'rails_helper'

RSpec.describe Voice::Livekit::EgressService do
  let(:call) { instance_double(Call, livekit_room_name: 'room-1', provider_call_id: 'room-1') }
  let(:recording) do
    instance_double(
      VoiceRecording,
      object_key: 'voice-recordings/account-1/call-1/room-1.mp4'
    )
  end

  describe '.start_room_composite' do
    it 'starts audio-only room composite egress with roomRecord permission' do
      egress_request = stub_request(:post, 'https://test.livekit.cloud/twirp/livekit.Egress/StartRoomCompositeEgress')
                       .with do |request|
        body = JSON.parse(request.body)
        token = request.headers.fetch('Authorization').delete_prefix('Bearer ')
        claims = JWT.decode(token, 'recording-secret', true, { algorithm: 'HS256' }).first

        expect(body).to include(
          'room_name' => 'room-1',
          'audio_only' => true
        )
        expect(body.fetch('file_outputs').first).to include(
          'filepath' => 'voice-recordings/account-1/call-1/room-1.mp4',
          's3' => hash_including(
            'bucket' => 'voice-recordings-test',
            'endpoint' => 'https://r2.example.test',
            'force_path_style' => true
          )
        )
        expect(claims.dig('video', 'roomRecord')).to be(true)
        expect(claims.dig('video', 'room')).to eq('room-1')
        expect(claims['iss']).to eq('recording-key')
      end.to_return(
        status: 200,
        body: { egress_id: 'EG_test', status: 'EGRESS_STARTING' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      result = with_modified_env(recording_env) do
        described_class.start_room_composite(call: call, recording: recording)
      end

      expect(result).to include(
        'status' => 'ok',
        'egress_id' => 'EG_test',
        'egress_status' => 'EGRESS_STARTING'
      )
      expect(egress_request).to have_been_requested
    end
  end

  describe '.stop' do
    it 'stops egress with roomRecord permission' do
      stop_request = stub_request(:post, 'https://test.livekit.cloud/twirp/livekit.Egress/StopEgress')
                     .with do |request|
        body = JSON.parse(request.body)
        token = request.headers.fetch('Authorization').delete_prefix('Bearer ')
        claims = JWT.decode(token, 'recording-secret', true, { algorithm: 'HS256' }).first

        expect(body).to eq('egress_id' => 'EG_test')
        expect(claims.dig('video', 'roomRecord')).to be(true)
        expect(claims.dig('video', 'room')).to eq('room-1')
        expect(claims['iss']).to eq('recording-key')
      end.to_return(
        status: 200,
        body: { egress_id: 'EG_test', status: 'EGRESS_COMPLETE' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      result = with_modified_env(recording_env) do
        described_class.stop(egress_id: 'EG_test', call: call)
      end

      expect(result).to include('status' => 'ok', 'egress_id' => 'EG_test')
      expect(stop_request).to have_been_requested
    end
  end

  def recording_env
    {
      'LIVEKIT_URL' => 'wss://test.livekit.cloud',
      'LIVEKIT_API_KEY' => 'livekit-key',
      'LIVEKIT_API_SECRET' => 'livekit-secret',
      'LIVEKIT_RECORDING_API_KEY' => 'recording-key',
      'LIVEKIT_RECORDING_API_SECRET' => 'recording-secret',
      'VOICE_RECORDING_S3_ACCESS_KEY_ID' => 'access-key',
      'VOICE_RECORDING_S3_SECRET_ACCESS_KEY' => 'secret-key',
      'VOICE_RECORDING_S3_BUCKET' => 'voice-recordings-test',
      'VOICE_RECORDING_S3_ENDPOINT' => 'https://r2.example.test',
      'VOICE_RECORDING_S3_FORCE_PATH_STYLE' => 'true'
    }
  end
end
