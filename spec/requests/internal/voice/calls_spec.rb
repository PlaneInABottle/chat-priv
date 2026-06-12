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
      setting = VoiceInboxSetting.find_by!(id: call.meta['voice_inbox_setting_id'])
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
      setting = VoiceInboxSetting.find_by!(id: call.meta['voice_inbox_setting_id'])
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
  end
end
