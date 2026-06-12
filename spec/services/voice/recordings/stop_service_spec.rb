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

  it 'marks the recording completed when StopEgress returns a complete egress response' do
    message = create(:message, account: call.account, inbox: call.inbox, conversation: call.conversation, content_type: 'voice_call')
    call.update!(message: message)
    recording = create(
      :voice_recording,
      call: call,
      status: 'active',
      egress_id: 'EG_complete',
      bucket: 'recordings',
      object_key: 'voice-recordings/account-1/call-1/original.mp4'
    )
    allow(Voice::Livekit::EgressService).to receive(:stop).and_return(
      {
        'status' => 'ok',
        'egress_id' => 'EG_complete',
        'egress_status' => 'EGRESS_COMPLETE',
        'response' => {
          'egress_id' => 'EG_complete',
          'status' => 'EGRESS_COMPLETE',
          'ended_at' => '1781295582063947754',
          'file_results' => [
            {
              'duration' => '19673051922',
              'location' => 's3://recordings/voice-recordings/account-1/call-1/final.ogg'
            }
          ]
        }
      }
    )

    described_class.perform(call: call)

    expect(recording.reload).to have_attributes(
      status: 'completed',
      duration_seconds: 20,
      object_key: 'voice-recordings/account-1/call-1/final.ogg',
      content_type: 'audio/ogg'
    )
    expect(message.reload.content_attributes.dig('data', 'recording')).to include(
      'id' => recording.id,
      'status' => 'completed'
    )
  end
end
