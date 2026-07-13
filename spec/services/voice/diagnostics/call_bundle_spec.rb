require 'rails_helper'

RSpec.describe Voice::Diagnostics::CallBundle do
  let(:account) { create(:account, settings: { voice_ai_enabled: true, ai_agent_enabled: true }) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:voice_agent) { create(:voice_agent, account: account) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      contact: conversation.contact,
      conversation: conversation,
      provider: :livekit,
      status: 'completed',
      provider_call_id: 'room-diagnostics',
      started_at: 2.minutes.ago,
      duration_seconds: 60,
      end_reason: 'caller_disconnected',
      meta: {
        'voice_agent_id' => voice_agent.id,
        'livekit_room_name' => 'room-diagnostics',
        'ai_status' => 'waiting',
        'livekit_room_delete' => { 'status' => 'failed', 'error' => 'room delete failed' }
      }
    )
  end

  it 'returns a redacted AI-readable diagnostic bundle by default' do
    call.transcript_segments.create!(
      account: account,
      conversation: conversation,
      role: 'caller',
      text: 'Email test@example.com telefon +90 555 111 22 33'
    )
    call.voice_tool_events.create!(
      account: account,
      tool: 'ikas_lookup_order',
      status: 'error',
      arguments: { email: 'test@example.com', phone: '+90 555 111 22 33' },
      result: { note: 'call +90 555 111 22 33' },
      error_message: 'lookup failed for test@example.com'
    )
    create(:voice_recording, account: account, call: call, status: 'failed', error_message: 'egress failed')

    payload = described_class.new(call: call, include_livekit: false, include_system_health: false).payload

    expect(payload[:redaction]).to include(mode: 'redacted')
    expect(payload[:failure_reasons]).to include(
      'agent_never_joined', 'call_ended_by_caller', 'livekit_room_delete_failed', 'recording_failed', 'tool_failed'
    )
    expect(payload[:transcript_segments].first[:text]).to eq('Email [email redacted] telefon [phone redacted]')
    expect(payload[:tool_events].first[:arguments]).to include('email' => '[email redacted]', 'phone' => '[phone redacted]')
    expect(payload[:tool_events].first[:result]).to include('note' => 'call [phone redacted]')
    expect(payload[:next_checks]).to include('Inspect voice agent worker health and LiveKit dispatch logs.')
  end

  it 'preserves raw content only when raw mode is explicit' do
    call.transcript_segments.create!(
      account: account,
      conversation: conversation,
      role: 'caller',
      text: 'Email test@example.com telefon +90 555 111 22 33'
    )

    payload = described_class.new(call: call, raw: true, include_livekit: false, include_system_health: false).payload

    expect(payload[:redaction]).to include(mode: 'raw')
    expect(payload[:transcript_segments].first[:text]).to eq('Email test@example.com telefon +90 555 111 22 33')
  end

  it 'flags recordings that are still active after a terminal call' do
    recording = create(:voice_recording, account: account, call: call, status: 'active')
    recording.update!(updated_at: Time.current)
    call.update!(updated_at: 5.minutes.ago)

    payload = described_class.new(call: call, include_livekit: false, include_system_health: false).payload

    expect(payload[:failure_reasons]).to include('recording_still_active_after_call_end')
    expect(payload[:next_checks]).to include(
      'Inspect LiveKit egress end webhook delivery and recording finalization cleanup.'
    )
  end

  it 'includes LiveKit room summary when requested' do
    allow(Voice::Livekit::RoomService).to receive(:participant_summary).with(call: call).and_return(
      'status' => 'active',
      'participant_count' => 2
    )

    payload = described_class.new(call: call, include_livekit: true, include_system_health: false).payload

    expect(payload.dig(:livekit, :room_summary)).to include('status' => 'active', 'participant_count' => 2)
  end
end
