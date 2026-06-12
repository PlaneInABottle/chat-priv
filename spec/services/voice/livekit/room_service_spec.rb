require 'rails_helper'

RSpec.describe Voice::Livekit::RoomService do
  let(:call) { instance_double(Call, livekit_room_name: 'room-1', provider_call_id: 'room-1') }

  describe '.remove_agent_participants' do
    it 'skips when LiveKit credentials are missing' do
      result = with_modified_env('LIVEKIT_URL' => nil, 'LIVEKIT_API_KEY' => nil, 'LIVEKIT_API_SECRET' => nil) do
        described_class.remove_agent_participants(call: call)
      end

      expect(result).to eq(
        {
          'status' => 'skipped',
          'reason' => 'livekit_room_service_not_configured'
        }
      )
    end

    it 'removes only LiveKit agent participants with a room admin token' do
      list_request = stub_request(:post, 'https://test.livekit.cloud/twirp/livekit.RoomService/ListParticipants')
                     .with do |request|
        body = JSON.parse(request.body)
        token = request.headers.fetch('Authorization').delete_prefix('Bearer ')
        claims = JWT.decode(token, 'livekit-secret', true, { algorithm: 'HS256' }).first

        expect(body).to include('room' => 'room-1')
        expect(claims.dig('video', 'roomAdmin')).to be(true)
        expect(claims.dig('video', 'room')).to eq('room-1')
      end.to_return(
        status: 200,
        body: {
          participants: [
            { identity: 'caller-1', kind: 'STANDARD' },
            { identity: 'agent-worker-1', kind: 'AGENT' },
            { identity: 'browser-agent-1', kind: 0 }
          ]
        }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
      remove_request = stub_request(:post, 'https://test.livekit.cloud/twirp/livekit.RoomService/RemoveParticipant')
                       .with do |request|
        body = JSON.parse(request.body)
        expect(body).to include('room' => 'room-1', 'identity' => 'agent-worker-1')
      end.to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      result = with_modified_env(
        'LIVEKIT_URL' => 'wss://test.livekit.cloud',
        'LIVEKIT_API_KEY' => 'livekit-key',
        'LIVEKIT_API_SECRET' => 'livekit-secret'
      ) do
        described_class.remove_agent_participants(call: call)
      end

      expect(result).to eq(
        {
          'status' => 'removed',
          'removed_identities' => ['agent-worker-1']
        }
      )
      expect(list_request).to have_been_requested
      expect(remove_request).to have_been_requested
    end
  end

  describe '.participant_summary' do
    it 'counts non-agent participants as customer participants' do
      stub_request(:post, 'https://test.livekit.cloud/twirp/livekit.RoomService/ListParticipants')
        .to_return(
          status: 200,
          body: {
            participants: [
              { identity: 'caller-account-1-user-1-call-1', kind: 'STANDARD' },
              { identity: 'agent-account-1-user-1-call-1', kind: 'STANDARD' },
              { identity: 'agent-worker-1', kind: 'AGENT' }
            ]
          }.to_json,
          headers: { 'Content-Type' => 'application/json' }
        )

      result = with_modified_env(
        'LIVEKIT_URL' => 'wss://test.livekit.cloud',
        'LIVEKIT_API_KEY' => 'livekit-key',
        'LIVEKIT_API_SECRET' => 'livekit-secret'
      ) do
        described_class.participant_summary(call: call)
      end

      expect(result).to include(
        'status' => 'active',
        'participant_count' => 3,
        'customer_participant_count' => 1,
        'agent_participant_count' => 2
      )
    end
  end

  describe '.delete_room' do
    it 'skips when LiveKit credentials are missing' do
      result = with_modified_env('LIVEKIT_URL' => nil, 'LIVEKIT_API_KEY' => nil, 'LIVEKIT_API_SECRET' => nil) do
        described_class.delete_room(call: call)
      end

      expect(result).to eq(
        {
          'status' => 'skipped',
          'reason' => 'livekit_room_service_not_configured'
        }
      )
    end

    it 'deletes the room with a roomCreate token' do
      delete_request = stub_request(:post, 'https://test.livekit.cloud/twirp/livekit.RoomService/DeleteRoom')
                       .with do |request|
        body = JSON.parse(request.body)
        token = request.headers.fetch('Authorization').delete_prefix('Bearer ')
        claims = JWT.decode(token, 'livekit-secret', true, { algorithm: 'HS256' }).first

        expect(body).to include('room' => 'room-1')
        expect(claims.dig('video', 'roomCreate')).to be(true)
        expect(claims.dig('video', 'room')).to eq('room-1')
      end.to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      result = with_modified_env(
        'LIVEKIT_URL' => 'wss://test.livekit.cloud',
        'LIVEKIT_API_KEY' => 'livekit-key',
        'LIVEKIT_API_SECRET' => 'livekit-secret'
      ) do
        described_class.delete_room(call: call)
      end

      expect(result).to eq(
        {
          'status' => 'deleted',
          'room' => 'room-1'
        }
      )
      expect(delete_request).to have_been_requested
    end
  end

  describe '.delete_room_name' do
    it 'deletes a room by name without a call record' do
      delete_request = stub_request(:post, 'https://test.livekit.cloud/twirp/livekit.RoomService/DeleteRoom')
                       .with do |request|
        body = JSON.parse(request.body)
        expect(body).to include('room' => 'sip-room-rejected')
      end.to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })

      result = with_modified_env(
        'LIVEKIT_URL' => 'wss://test.livekit.cloud',
        'LIVEKIT_API_KEY' => 'livekit-key',
        'LIVEKIT_API_SECRET' => 'livekit-secret'
      ) do
        described_class.delete_room_name(room_name: 'sip-room-rejected')
      end

      expect(result).to include('status' => 'deleted', 'room' => 'sip-room-rejected')
      expect(delete_request).to have_been_requested
    end
  end
end
