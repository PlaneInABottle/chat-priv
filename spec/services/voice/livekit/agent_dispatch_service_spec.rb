require 'rails_helper'

RSpec.describe Voice::Livekit::AgentDispatchService do
  let(:call) { instance_double(Call, livekit_room_name: 'room-1', provider_call_id: 'room-1') }

  describe '.perform' do
    it 'skips dispatch when LiveKit credentials are missing' do
      result = with_modified_env('LIVEKIT_URL' => nil, 'LIVEKIT_API_KEY' => nil, 'LIVEKIT_API_SECRET' => nil) do
        described_class.perform(call: call)
      end

      expect(result).to eq(
        {
          'status' => 'skipped',
          'reason' => 'livekit_dispatch_not_configured'
        }
      )
    end

    it 'creates an explicit agent dispatch with a room admin token' do
      dispatch_request = stub_request(:post, 'https://test.livekit.cloud/twirp/livekit.AgentDispatchService/CreateDispatch')
                         .with do |request|
        body = JSON.parse(request.body)
        token = request.headers.fetch('Authorization').delete_prefix('Bearer ')
        claims = JWT.decode(token, 'livekit-secret', true, { algorithm: 'HS256' }).first

        expect(body).to include(
          'agent_name' => 'test-voice-agent',
          'room' => 'room-1'
        )
        expect(JSON.parse(body.fetch('metadata'))).to include('call_id' => 123)
        expect(claims.dig('video', 'roomAdmin')).to be(true)
        expect(claims.dig('video', 'room')).to eq('room-1')
      end.to_return(
        status: 200,
        body: {
          id: 'AD_test',
          agent_name: 'test-voice-agent',
          room: 'room-1'
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )

      result = with_modified_env(
        'LIVEKIT_URL' => 'wss://test.livekit.cloud',
        'LIVEKIT_API_KEY' => 'livekit-key',
        'LIVEKIT_API_SECRET' => 'livekit-secret',
        'VOICE_AGENT_NAME' => 'test-voice-agent'
      ) do
        described_class.perform(call: call, metadata: { call_id: 123 })
      end

      expect(result).to eq(
        {
          'status' => 'dispatched',
          'dispatch_id' => 'AD_test',
          'agent_name' => 'test-voice-agent',
          'room' => 'room-1'
        }
      )
      expect(dispatch_request).to have_been_requested
    end
  end
end
