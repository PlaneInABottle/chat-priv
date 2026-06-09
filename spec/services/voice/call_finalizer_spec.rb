require 'rails_helper'

RSpec.describe Voice::CallFinalizer do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }

  before do
    allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return({ 'status' => 'skipped' })
  end

  def build_conversation_call
    Voice::InboundCallBuilder.perform!(
      inbox: inbox,
      from_number: '+905551112233',
      call_sid: "room-#{SecureRandom.hex(4)}",
      provider: :livekit,
      extra_meta: {
        'livekit_room_name' => "room-#{SecureRandom.hex(4)}",
        'handoff_status' => 'none',
        'ai_status' => 'waiting'
      }
    ).tap do |call|
      call.update!(started_at: Time.zone.now, status: 'in_progress')
    end
  end

  it 'marks a sandbox test call terminal without a conversation message' do
    started_at = Time.zone.now.change(usec: 0) - 2.minutes
    call = Voice::TestCallBuilder.perform!(account: account, inbox: inbox)
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

  it 'keeps terminal calls idempotent' do
    call = Voice::TestCallBuilder.perform!(account: account, inbox: inbox)
    described_class.perform!(call: call, end_reason: 'first_end')

    expect do
      described_class.perform!(call: call.reload, end_reason: 'second_end')
    end.not_to(change { call.reload.end_reason })
  end
end
