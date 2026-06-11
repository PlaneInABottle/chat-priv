require 'rails_helper'

RSpec.describe Voice::Recordings::StopService do
  let(:call) { create(:call, provider: :livekit, provider_call_id: 'room-1') }

  it 'skips when the call has no active recording' do
    result = described_class.perform(call: call)

    expect(result).to eq('status' => 'skipped', 'reason' => 'no_active_recording')
  end

  it 'stops the active LiveKit egress and stores the stop result' do
    recording = create(:voice_recording, call: call, status: 'active', egress_id: 'EG_active')
    allow(Voice::Livekit::EgressService).to receive(:stop).and_return({ 'status' => 'ok', 'egress_id' => 'EG_active' })

    result = described_class.perform(call: call)

    expect(result).to eq('status' => 'ok', 'egress_id' => 'EG_active')
    expect(Voice::Livekit::EgressService).to have_received(:stop).with(egress_id: 'EG_active', call: call)
    expect(recording.reload.metadata).to include('stop_result' => { 'status' => 'ok', 'egress_id' => 'EG_active' })
  end
end
