require 'rails_helper'

RSpec.describe Voice::Livekit::StaleCallFinalizer do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:voice_agent) { create(:voice_agent, account: account) }
  let(:voice_inbox_setting) { create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent) }

  before do
    allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return({ 'status' => 'skipped' })
  end

  it 'finalizes active calls whose LiveKit room no longer exists' do
    call = stale_call
    allow(Voice::Livekit::RoomService).to receive(:participant_summary).with(call: call).and_return(
      { 'status' => 'not_found' }
    )

    result = described_class.perform!(account: account)

    expect(result).to contain_exactly(call)
    expect(call.reload).to have_attributes(status: 'completed', end_reason: 'livekit_room_not_found')
    expect(call.meta.dig('livekit_stale_check', 'status')).to eq('not_found')
    expect(call.meta.dig('livekit_stale_check', 'ended_reason')).to eq('livekit_room_not_found')
  end

  it 'finalizes active calls without customer participants' do
    call = stale_call
    allow(Voice::Livekit::RoomService).to receive(:participant_summary).with(call: call).and_return(
      { 'status' => 'active', 'customer_participant_count' => 0, 'agent_participant_count' => 1 }
    )

    described_class.perform!(account: account)

    expect(call.reload).to have_attributes(status: 'completed', end_reason: 'livekit_no_customer_participants')
  end

  it 'keeps active calls with a customer participant open' do
    call = stale_call
    allow(Voice::Livekit::RoomService).to receive(:participant_summary).with(call: call).and_return(
      { 'status' => 'active', 'customer_participant_count' => 1, 'agent_participant_count' => 1 }
    )

    result = described_class.perform!(account: account)

    expect(result).to be_empty
    expect(call.reload.status).to eq('in_progress')
  end

  it 'uses the fallback timeout when LiveKit state cannot be checked' do
    account.update!(voice_ai_max_call_duration_minutes: 180)
    call = stale_call(started_at: 2.hours.ago)
    allow(Voice::Livekit::RoomService).to receive(:participant_summary).with(call: call).and_return(
      { 'status' => 'failed', 'error' => 'timeout' }
    )

    described_class.perform!(account: account)

    expect(call.reload).to have_attributes(status: 'completed', end_reason: 'stale_timeout')
  end

  it 'finalizes calls that exceed the account max duration' do
    account.update!(voice_ai_max_call_duration_minutes: 10)
    call = stale_call(started_at: 11.minutes.ago)
    allow(Voice::Livekit::RoomService).to receive(:participant_summary)

    described_class.perform!(account: account)

    expect(call.reload).to have_attributes(status: 'completed', end_reason: 'voice_max_duration_exceeded')
    expect(Voice::Livekit::RoomService).not_to have_received(:participant_summary)
  end

  def stale_call(started_at: 10.minutes.ago)
    voice_inbox_setting
    Voice::TestCallBuilder.perform!(account: account, inbox: inbox, voice_agent: voice_agent).tap do |call|
      call.update!(started_at: started_at)
    end
  end
end
