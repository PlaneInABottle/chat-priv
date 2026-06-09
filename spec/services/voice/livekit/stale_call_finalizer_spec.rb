require 'rails_helper'

RSpec.describe Voice::Livekit::StaleCallFinalizer do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }

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
    call = stale_call(started_at: 2.hours.ago)
    allow(Voice::Livekit::RoomService).to receive(:participant_summary).with(call: call).and_return(
      { 'status' => 'failed', 'error' => 'timeout' }
    )

    described_class.perform!(account: account)

    expect(call.reload).to have_attributes(status: 'completed', end_reason: 'stale_timeout')
  end

  def stale_call(started_at: 10.minutes.ago)
    Voice::TestCallBuilder.perform!(account: account, inbox: inbox).tap do |call|
      call.update!(started_at: started_at)
    end
  end
end
