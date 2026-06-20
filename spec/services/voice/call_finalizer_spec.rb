require 'rails_helper'

RSpec.describe Voice::CallFinalizer do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:voice_agent) { account.voice_agents.first! }
  let!(:voice_inbox_setting) { create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent) }

  before do
    allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return({ 'status' => 'skipped' })
    allow(Voice::Livekit::RoomService).to receive(:remove_customer_participants).and_return({ 'status' => 'skipped' })
    allow(Voice::Livekit::RoomService).to receive(:delete_room).and_return({ 'status' => 'skipped' })
  end

  def build_conversation_call
    Voice::InboundCallBuilder.perform!(
      inbox: inbox,
      from_number: '+905551112233',
      call_sid: "room-#{SecureRandom.hex(4)}",
      provider: :livekit,
      extra_meta: {
        'livekit_room_name' => "room-#{SecureRandom.hex(4)}",
        'voice_inbox_setting_id' => voice_inbox_setting.id,
        'handoff_status' => 'none',
        'ai_status' => 'waiting'
      }
    ).tap do |call|
      call.update!(started_at: Time.zone.now, status: 'in_progress')
    end
  end

  it 'marks a sandbox test call terminal without a conversation message' do
    started_at = Time.zone.now.change(usec: 0) - 2.minutes
    call = Voice::TestCallBuilder.perform!(account: account, inbox: inbox, voice_agent: voice_agent)
    call.update!(started_at: started_at)

    travel_to(started_at + 45.seconds) do
      described_class.perform!(call: call, end_reason: 'caller_disconnected')
    end

    expect(call.reload).to have_attributes(
      status: 'completed',
      duration_seconds: 45,
      end_reason: 'caller_disconnected'
    )
    expect(call.message).to be_nil
  end

  it 'marks a conversation call terminal and refreshes the voice-call message payload' do
    started_at = Time.zone.now.change(usec: 0) - 2.minutes
    call = build_conversation_call
    call.update!(started_at: started_at)

    travel_to(started_at + 45.seconds) do
      described_class.perform!(call: call, end_reason: 'caller_disconnected')
    end

    expect(call.reload).to have_attributes(
      status: 'completed',
      duration_seconds: 45,
      end_reason: 'caller_disconnected'
    )
    expect(call.message.reload.content_attributes['data']).to include(
      'status' => 'completed',
      'duration_seconds' => 45
    )
  end

  it 'stops active LiveKit recordings when ending a call' do
    call = build_conversation_call
    create(:voice_recording, call: call, status: 'active', egress_id: 'EG_active')
    allow(Voice::Recordings::StopService).to receive(:perform).and_return({ 'status' => 'ok' })

    described_class.perform!(call: call, end_reason: 'agent_ended')

    expect(Voice::Recordings::StopService).to have_received(:perform).with(call: call)
  end

  it 'terminates the LiveKit room when ending a LiveKit call' do
    call = build_conversation_call
    allow(Voice::Livekit::RoomService).to receive(:remove_customer_participants).with(call: call).and_return(
      { 'status' => 'removed', 'removed_identities' => ['sip_+905551112233'] }
    )
    allow(Voice::Livekit::RoomService).to receive(:delete_room).with(call: call).and_return(
      { 'status' => 'deleted', 'room' => call.livekit_room_name }
    )

    described_class.perform!(call: call, end_reason: 'agent_ended')

    expect(Voice::Livekit::RoomService).to have_received(:remove_customer_participants).with(call: call)
    expect(Voice::Livekit::RoomService).to have_received(:delete_room).with(call: call)
    expect(call.reload.meta['livekit_customer_removal']).to eq(
      'status' => 'removed',
      'removed_identities' => ['sip_+905551112233']
    )
    expect(call.reload.meta['livekit_room_delete']).to eq(
      'status' => 'deleted',
      'room' => call.livekit_room_name
    )
  end

  it 'keeps terminal calls idempotent' do
    call = Voice::TestCallBuilder.perform!(account: account, inbox: inbox, voice_agent: voice_agent)
    allow(Voice::Recordings::StopService).to receive(:perform)
    described_class.perform!(call: call, end_reason: 'first_end')

    expect do
      described_class.perform!(call: call.reload, end_reason: 'second_end')
    end.not_to(change { call.reload.end_reason })
    expect(Voice::Livekit::RoomService).to have_received(:delete_room).once
    expect(Voice::Recordings::StopService).to have_received(:perform).once
  end

  it 'does not run cleanup for an already terminal call' do
    call = build_conversation_call
    call.update!(status: 'completed', duration_seconds: 10, end_reason: 'already_ended')
    allow(Voice::Recordings::StopService).to receive(:perform)

    described_class.perform!(call: call, end_reason: 'second_end')

    expect(Voice::Livekit::RoomService).not_to have_received(:remove_customer_participants)
    expect(Voice::Livekit::RoomService).not_to have_received(:delete_room)
    expect(Voice::Recordings::StopService).not_to have_received(:perform)
    expect(call.reload).to have_attributes(
      status: 'completed',
      duration_seconds: 10,
      end_reason: 'already_ended'
    )
  end
end
