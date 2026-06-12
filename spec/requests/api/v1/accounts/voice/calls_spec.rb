require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Voice::Calls', type: :request do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:voice_agent) { account.voice_agents.first! }
  let!(:voice_inbox_setting) { create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent) }
  let(:call) { Voice::TestCallBuilder.perform!(account: account, inbox: inbox, voice_agent: voice_agent) }
  let(:conversation_call) { build_conversation_call }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
    allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return({ 'status' => 'skipped' })
    allow(Voice::Livekit::RoomService).to receive(:remove_agent_participants).and_return(
      {
        'status' => 'removed',
        'removed_identities' => ['agent-worker-1']
      }
    )
    allow(Voice::Livekit::RoomService).to receive(:delete_room).and_return({ 'status' => 'deleted', 'room' => 'room-1' })
  end

  def build_conversation_call
    setting = voice_inbox_setting
    Voice::InboundCallBuilder.perform!(
      inbox: inbox,
      from_number: '+905551112233',
      call_sid: "room-#{SecureRandom.hex(4)}",
      provider: :livekit,
      extra_meta: {
        'livekit_room_name' => "room-#{SecureRandom.hex(4)}",
        'voice_inbox_setting_id' => setting.id,
        'handoff_status' => 'none',
        'ai_status' => 'waiting'
      }
    ).tap do |created_call|
      created_call.update!(started_at: Time.zone.now, status: 'in_progress')
    end
  end

  describe 'GET /api/v1/accounts/:account_id/voice/calls/:id' do
    it 'does not expose raw voice tool events for conversation-backed calls' do
      conversation_call.voice_tool_events.create!(
        account: account,
        tool: 'request_human_handoff',
        status: 'executed',
        arguments: { reason: 'private handoff reason' },
        result: { internal_note: 'private note' },
        source: 'livekit_agent'
      )

      get "/api/v1/accounts/#{account.id}/voice/calls/#{conversation_call.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).not_to have_key('tool_events')
      expect(response.body).not_to include('private handoff reason', 'private note')
    end

    it 'exposes sanitized voice tool events for sandbox test calls' do
      call.voice_tool_events.create!(
        account: account,
        tool: 'request_human_handoff',
        status: 'executed',
        arguments: { reason: 'caller gave test@example.com and +905551112233' },
        result: { internal_note: 'private note' },
        source: 'livekit_agent'
      )

      get "/api/v1/accounts/#{account.id}/voice/calls/#{call.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['tool_events'].first).to include(
        'tool' => 'request_human_handoff',
        'status' => 'executed',
        'arguments' => { 'reason' => 'caller gave [email redacted] and [phone redacted]' }
      )
    end
  end

  describe 'POST /api/v1/accounts/:account_id/voice/calls/:id/take_over' do
    it 'assigns the call to the agent, silences AI state, and refreshes the message payload' do
      post "/api/v1/accounts/#{account.id}/voice/calls/#{conversation_call.id}/take_over",
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(Voice::Livekit::RoomService).to have_received(:remove_agent_participants).with(call: conversation_call)
      expect(conversation_call.reload).to have_attributes(
        accepted_by_agent: agent,
        handoff_status: 'accepted',
        ai_status: 'silent'
      )
      expect(conversation_call.meta.dig('livekit_agent_removal', 'status')).to eq('removed')
      expect(conversation_call.conversation.reload.assignee).to eq(agent)
      expect(conversation_call.message.reload.content_attributes['data']).to include(
        'status' => 'in-progress',
        'handoff_status' => 'accepted',
        'ai_status' => 'silent',
        'accepted_by' => { 'id' => agent.id, 'name' => agent.name }
      )
    end

    it 'does not reopen an ended call' do
      conversation_call.update!(status: 'completed')

      post "/api/v1/accounts/#{account.id}/voice/calls/#{conversation_call.id}/take_over",
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(Voice::Livekit::RoomService).not_to have_received(:remove_agent_participants)
      expect(conversation_call.reload).to have_attributes(
        status: 'completed',
        accepted_by_agent: nil
      )
    end

    it 'rejects sandbox test calls because they have no conversation to hand off' do
      post "/api/v1/accounts/#{account.id}/voice/calls/#{call.id}/take_over",
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => 'Call handoff requires a conversation')
      expect(Voice::Livekit::RoomService).not_to have_received(:remove_agent_participants)
    end
  end

  describe 'POST /api/v1/accounts/:account_id/voice/calls/:id/token' do
    it 'includes the browser session id in the LiveKit participant identity' do
      service = instance_double(Voice::Livekit::TokenService, payload: { identity: 'token-identity' })

      expect(Voice::Livekit::TokenService).to receive(:new) do |args|
        expect(args[:call]).to eq(call)
        expect(args[:identity]).to eq("agent-account-#{account.id}-user-#{agent.id}-call-#{call.id}-session-tab-a")
        expect(args[:name]).to eq(agent.available_name)
        service
      end

      post "/api/v1/accounts/#{account.id}/voice/calls/#{call.id}/token",
           params: { participant_type: 'agent', client_session_id: 'tab-a' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to eq('identity' => 'token-identity')
    end

    it 'does not issue a LiveKit token for an ended call' do
      call.update!(status: 'completed')

      post "/api/v1/accounts/#{account.id}/voice/calls/#{call.id}/token",
           params: { participant_type: 'agent' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => 'Call has already ended')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/voice/calls/:id/end' do
    it 'ends a conversation-backed LiveKit call and deletes the room' do
      post "/api/v1/accounts/#{account.id}/voice/calls/#{conversation_call.id}/end",
           params: { end_reason: 'agent_ended' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(Voice::Livekit::RoomService).to have_received(:delete_room).with(call: conversation_call)
      expect(response.parsed_body).to include(
        'id' => conversation_call.id,
        'status' => 'completed',
        'end_reason' => 'agent_ended'
      )
      expect(conversation_call.reload).to have_attributes(
        status: 'completed',
        end_reason: 'agent_ended'
      )
      expect(conversation_call.message.reload.content_attributes['data']).to include(
        'status' => 'completed'
      )
    end

    it 'keeps ending an already-ended call idempotent' do
      call.update!(status: 'completed', duration_seconds: 10, end_reason: 'already_ended')

      post "/api/v1/accounts/#{account.id}/voice/calls/#{call.id}/end",
           params: { end_reason: 'agent_ended' },
           headers: agent.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(call.reload).to have_attributes(
        status: 'completed',
        duration_seconds: 10,
        end_reason: 'already_ended'
      )
    end
  end
end
