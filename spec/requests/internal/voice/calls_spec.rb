require 'rails_helper'

RSpec.describe 'Internal voice calls API', type: :request do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:voice_agent) { account.voice_agents.first! }
  let!(:voice_inbox_setting) { create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent) }
  let(:call) { Voice::TestCallBuilder.perform!(account: account, inbox: inbox, voice_agent: voice_agent) }
  let(:conversation_call) { build_conversation_call }
  let(:path) { "/internal/voice/calls/#{call.provider_call_id}/transcript" }

  before do
    allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return({ 'status' => 'skipped' })
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

  describe 'POST /internal/voice/calls/:provider_call_id/transcript' do
    it 'persists transcript with the internal token' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { role: 'caller', text: 'Merhaba', source: 'livekit_agent', external_segment_id: 'turn-1' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:created)
      expect(call.transcript_segments.count).to eq(1)
      expect(call.reload.transcript).to eq('caller: Merhaba')
    end

    it 'rejects missing or wrong tokens' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { role: 'caller', text: 'Merhaba' },
             headers: { 'X-Voice-Agent-Token' => 'wrong' },
             as: :json
      end

      expect(response).to have_http_status(:unauthorized)
      expect(call.transcript_segments.count).to eq(0)
    end

    it 'returns validation errors as json' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { role: 'caller', text: 'Merhaba', source: 'unknown_source' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to include('Source is not included in the list')
      expect(call.transcript_segments.count).to eq(0)
    end
  end

  describe 'POST /internal/voice/calls/:provider_call_id/event' do
    let(:path) { "/internal/voice/calls/#{conversation_call.provider_call_id}/event" }

    it 'marks the AI active when the worker starts listening' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { event: 'agent_listening', payload: { participant_identity: 'sip_+905551112233' } },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:ok)
      conversation_call.reload
      expect(conversation_call.ai_status).to eq('active')
      expect(conversation_call.meta).to include(
        'last_voice_agent_event' => 'agent_listening',
        'last_voice_agent_payload' => { 'participant_identity' => 'sip_+905551112233' }
      )
      expect(conversation_call.message.content_attributes.dig('data', 'ai_status')).to eq('active')
    end
  end

  describe 'POST /internal/voice/calls/:provider_call_id/tool_call' do
    let(:path) { "/internal/voice/calls/#{call.provider_call_id}/tool_call" }

    it 'stores sanitized voice tool events with the internal token' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: {
               tool: 'request_human_handoff',
               status: 'executed',
               arguments: { reason: 'caller gave test@example.com and +905551112233' },
               result: { tool_status: 'ok' },
               duration_ms: 42,
               external_id: 'tool-call-1'
             },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:created)
      event = call.reload.voice_tool_events.order(:created_at).last
      expect(event).to have_attributes(
        tool: 'request_human_handoff',
        status: 'executed',
        duration_ms: 42,
        result: { 'tool_status' => 'ok' }
      )
      expect(event.arguments['reason']).to eq('caller gave [email redacted] and [phone redacted]')
      expect(event.external_id).to eq('tool-call-1')
      expect(Voice::CallSerializer.new(call).payload[:tool_events].first).to include(
        tool: 'request_human_handoff',
        arguments: { 'reason' => 'caller gave [email redacted] and [phone redacted]' }
      )
    end
  end

  describe 'GET /internal/voice/calls/:provider_call_id/agent_context' do
    let(:path) { "/internal/voice/calls/#{call.provider_call_id}/agent_context" }

    it 'returns the selected voice agent prompt and voice tools' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        get path,
            headers: { 'X-Voice-Agent-Token' => 'secret' },
            as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('voice_agent', 'id')).to eq(call.meta['voice_agent_id'])
      expect(response.parsed_body['instructions']).to include('Voice agent instructions')
      expect(response.parsed_body['tools'].pluck('key')).to include('human_handoff', 'end_customer_call')
    end

    it 'rejects voice agent metadata from another account' do
      other_voice_agent = create(:voice_agent, account: create(:account), name: 'Foreign voice agent')
      setting = VoiceInboxSetting.find(call.meta['voice_inbox_setting_id'])
      setting.update!(voice_agent: nil)
      call.update!(
        meta: call.meta.merge(
          'voice_inbox_setting_id' => nil,
          'voice_agent_id' => other_voice_agent.id
        )
      )

      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        get path,
            headers: { 'X-Voice-Agent-Token' => 'secret' },
            as: :json
      end

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to include('Voice agent not configured')
    end

    it 'returns not found when no account-scoped voice agent can be resolved' do
      setting = VoiceInboxSetting.find(call.meta['voice_inbox_setting_id'])
      setting.update!(voice_agent: nil)
      account.voice_agents.destroy_all
      call.update!(meta: call.meta.merge('voice_agent_id' => nil))

      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        get path,
            headers: { 'X-Voice-Agent-Token' => 'secret' },
            as: :json
      end

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to include('Voice agent not configured')
    end
  end

  describe 'POST /internal/voice/calls/:provider_call_id/agent_context' do
    it 'bootstraps a real SIP-dispatched LiveKit call from voice number metadata' do
      provider_connection = create(:voice_provider_connection, account: account, provider: 'test_sip')
      voice_number = create(
        :voice_number,
        account: account,
        voice_provider_connection: provider_connection,
        voice_inbox_setting: voice_inbox_setting,
        phone_number: '+908501112234'
      )
      allow(Voice::Recordings::StartService).to receive(:perform)

      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        expect do
          post '/internal/voice/calls/sip-room-agent-context/agent_context',
               params: {
                 metadata: {
                   account_id: account.id,
                   voice_number_id: voice_number.id,
                   from_number: '+905551112233',
                   to_number: '+908501112234'
                 }
               },
               headers: { 'X-Voice-Agent-Token' => 'secret' },
               as: :json
        end.to change(Call.livekit, :count).by(1)
      end

      expect(response).to have_http_status(:ok)
      created_call = Call.livekit.find_by!(provider_call_id: 'sip-room-agent-context')
      expect(created_call).to have_attributes(account_id: account.id, inbox_id: inbox.id, status: 'in_progress')
      expect(created_call.meta).to include(
        'voice_number_id' => voice_number.id,
        'voice_provider_connection_id' => provider_connection.id,
        'voice_inbox_setting_id' => voice_inbox_setting.id,
        'voice_agent_id' => voice_agent.id
      )
      expect(response.parsed_body.dig('voice_agent', 'id')).to eq(voice_agent.id)
    end

    it 'returns not found when SIP metadata cannot be routed' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        expect do
          post '/internal/voice/calls/sip-room-unmatched/agent_context',
               params: { metadata: { to_number: '+908509999999' } },
               headers: { 'X-Voice-Agent-Token' => 'secret' },
               as: :json
        end.not_to change(Call.livekit, :count)
      end

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to include('Voice number or voice inbox setting not configured')
    end

    it 'rejects voice number metadata scoped to another account' do
      provider_connection = create(:voice_provider_connection, account: account, provider: 'test_sip')
      voice_number = create(
        :voice_number,
        account: account,
        voice_provider_connection: provider_connection,
        voice_inbox_setting: voice_inbox_setting,
        phone_number: '+908501112236'
      )
      foreign_account = create(:account, settings: { voice_ai_enabled: true })

      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        expect do
          post '/internal/voice/calls/sip-room-foreign-number/agent_context',
               params: {
                 metadata: {
                   account_id: foreign_account.id,
                   voice_number_id: voice_number.id,
                   to_number: '+908501112236'
                 }
               },
               headers: { 'X-Voice-Agent-Token' => 'secret' },
               as: :json
        end.not_to change(Call.livekit, :count)
      end

      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body['error']).to include('Voice number or voice inbox setting not configured')
    end

    it 'returns a limit response and deletes the LiveKit room when concurrent call admission rejects the call' do
      account.update!(voice_ai_concurrent_call_limit: 1)
      provider_connection = create(:voice_provider_connection, account: account, provider: 'test_sip')
      voice_number = create(
        :voice_number,
        account: account,
        voice_provider_connection: provider_connection,
        voice_inbox_setting: voice_inbox_setting,
        phone_number: '+908501112235'
      )
      create(:call, account: account, inbox: inbox, provider: :livekit, status: 'in_progress')
      allow(Voice::Livekit::RoomService).to receive(:delete_room_name).and_return(
        { 'status' => 'deleted', 'room' => 'sip-room-limit' }
      )

      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        expect do
          post '/internal/voice/calls/sip-room-limit/agent_context',
               params: {
                 metadata: {
                   account_id: account.id,
                   voice_number_id: voice_number.id,
                   to_number: '+908501112235'
                 }
               },
               headers: { 'X-Voice-Agent-Token' => 'secret' },
               as: :json
        end.not_to change(Call.livekit, :count)
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.parsed_body).to include(
        'error' => 'Voice AI concurrent call limit is reached.',
        'error_code' => 'voice_usage_rejected'
      )
      expect(Voice::Livekit::RoomService).to have_received(:delete_room_name).with(room_name: 'sip-room-limit')
    end
  end

  describe 'POST /internal/voice/calls/:provider_call_id/tools/:tool_key/execute' do
    let(:path) { "/internal/voice/calls/#{call.provider_call_id}/tools/human_handoff/execute" }

    it 'executes and records a voice tool through the runtime endpoint' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { arguments: { reason: 'caller requested a human' }, external_id: 'runtime-tool-1' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['status']).to eq('executed')
      event = call.reload.voice_tool_events.find_by!(external_id: 'runtime-tool-1')
      expect(event).to have_attributes(tool: 'human_handoff', status: 'executed')
      expect(call.handoff_status).to eq('requested')
    end

    it 'rejects tool execution when Voice AI is disabled' do
      call
      account.update!(voice_ai_enabled: false)
      allow(VoiceAgents::ToolExecutor).to receive(:perform!)

      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { arguments: { reason: 'caller requested a human' }, external_id: 'runtime-tool-disabled' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'Voice AI is disabled for this account.')
      expect(VoiceAgents::ToolExecutor).not_to have_received(:perform!)
    end

    it 'rejects tool execution for terminal calls' do
      call.update!(status: 'completed')
      allow(VoiceAgents::ToolExecutor).to receive(:perform!)

      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { arguments: { reason: 'caller requested a human' }, external_id: 'runtime-tool-terminal' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => 'Call has already ended')
      expect(VoiceAgents::ToolExecutor).not_to have_received(:perform!)
    end
  end

  describe 'POST /internal/voice/calls/:provider_call_id/handoff' do
    let(:path) { "/internal/voice/calls/#{conversation_call.provider_call_id}/handoff" }
    let(:team) { create(:team, account: account) }

    before do
      setting = VoiceInboxSetting.find_or_create_by!(account: account, inbox: inbox)
      setting.update!(fallback_team: team)
      conversation_call
    end

    it 'marks handoff requested and refreshes the voice call message payload' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { reason: 'caller requested a human' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(conversation_call.reload.handoff_status).to eq('requested')
      expect(conversation_call.ai_status).to eq('handoff_requested')
      expect(conversation_call.conversation.reload.team).to eq(team)
      expect(conversation_call.message.reload.content_attributes['data']).to include(
        'call_id' => conversation_call.id,
        'call_source' => 'livekit',
        'status' => 'in-progress',
        'handoff_status' => 'requested',
        'ai_status' => 'handoff_requested'
      )
    end

    it 'marks sandbox test handoff requested without creating a conversation' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post "/internal/voice/calls/#{call.provider_call_id}/handoff",
             params: { reason: 'caller requested a human' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(call.reload).to have_attributes(handoff_status: 'requested', ai_status: 'handoff_requested')
      expect(call.conversation).to be_nil
      expect(response.parsed_body).to include(
        'tool_status' => 'ok',
        'terminal_action' => 'handoff',
        'test_mode' => true,
        'reason' => 'caller requested a human'
      )
    end

    it 'rejects handoff when Voice AI is disabled' do
      account.update!(voice_ai_enabled: false)

      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { reason: 'caller requested a human' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body).to eq('error' => 'Voice AI is disabled for this account.')
      expect(conversation_call.reload.handoff_status).to eq('none')
    end

    it 'rejects handoff for terminal calls' do
      conversation_call.update!(status: 'completed')

      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { reason: 'caller requested a human' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body).to eq('error' => 'Call has already ended')
      expect(conversation_call.reload.handoff_status).to eq('none')
    end
  end
end
