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

  it 'reconciles a recording when StopEgress reports the egress already completed' do
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
        'status' => 'failed',
        'code' => '412',
        'error' => 'egress with status EGRESS_COMPLETE cannot be stopped'
      }
    )
    allow(Voice::Livekit::EgressService).to receive(:fetch).and_return(completed_lookup_result)

    result = described_class.perform(call: call)

    expect(result).to include('status' => 'ok', 'egress_id' => 'EG_complete')
    expect(Voice::Livekit::EgressService).to have_received(:fetch).with(egress_id: 'EG_complete', call: call)
    expect(recording.reload).to have_attributes(
      status: 'completed',
      duration_seconds: 20,
      object_key: 'voice-recordings/account-1/call-1/final.ogg',
      content_type: 'audio/ogg'
    )
    expect(recording.metadata).to include(
      'stop_result' => hash_including('status' => 'failed', 'code' => '412'),
      'stop_reconcile_result' => hash_including('status' => 'ok', 'egress_id' => 'EG_complete')
    )
    expect(message.reload.content_attributes.dig('data', 'recording')).to include(
      'id' => recording.id,
      'status' => 'completed'
    )
  end

  it 'reconciles a recording when StopEgress is still ending' do
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
        'egress_status' => 'EGRESS_ENDING',
        'response' => {
          'egress_id' => 'EG_complete',
          'status' => 'EGRESS_ENDING'
        }
      }
    )
    allow(Voice::Livekit::EgressService).to receive(:fetch).and_return(completed_lookup_result)

    result = described_class.perform(call: call)

    expect(result).to include('status' => 'ok', 'egress_id' => 'EG_complete')
    expect(Voice::Livekit::EgressService).to have_received(:fetch).with(egress_id: 'EG_complete', call: call)
    expect(recording.reload).to have_attributes(
      status: 'completed',
      duration_seconds: 20,
      object_key: 'voice-recordings/account-1/call-1/final.ogg',
      content_type: 'audio/ogg'
    )
    expect(recording.metadata).to include(
      'stop_result' => hash_including('status' => 'ok', 'egress_status' => 'EGRESS_ENDING'),
      'stop_reconcile_result' => hash_including('status' => 'ok', 'egress_id' => 'EG_complete')
    )
    expect(message.reload.content_attributes.dig('data', 'recording')).to include(
      'id' => recording.id,
      'status' => 'completed'
    )
  end

  it 'marks the recording failed when StopEgress reports the egress already aborted' do
    message = create(:message, account: call.account, inbox: call.inbox, conversation: call.conversation, content_type: 'voice_call')
    call.update!(message: message)
    recording = create(
      :voice_recording,
      call: call,
      status: 'active',
      egress_id: 'EG_aborted',
      bucket: 'recordings'
    )
    allow(Voice::Livekit::EgressService).to receive(:stop).and_return(
      {
        'status' => 'failed',
        'code' => '412',
        'error' => 'egress with status EGRESS_ABORTED cannot be stopped'
      }
    )
    allow(Voice::Livekit::EgressService).to receive(:fetch).and_return(aborted_lookup_result)

    result = described_class.perform(call: call)

    expect(result).to include('status' => 'ok', 'egress_id' => 'EG_aborted')
    expect(Voice::Livekit::EgressService).to have_received(:fetch).with(egress_id: 'EG_aborted', call: call)
    expect(recording.reload).to have_attributes(
      status: 'failed',
      error_message: 'room closed before media was written'
    )
    expect(recording.metadata).to include(
      'stop_result' => hash_including('status' => 'failed', 'code' => '412'),
      'stop_reconcile_result' => hash_including('status' => 'ok', 'egress_id' => 'EG_aborted')
    )
    expect(message.reload.content_attributes.dig('data', 'recording')).to include(
      'id' => recording.id,
      'status' => 'failed'
    )
  end

  it 'marks the recording failed when an already-aborted egress cannot be fetched' do
    message = create(:message, account: call.account, inbox: call.inbox, conversation: call.conversation, content_type: 'voice_call')
    call.update!(message: message)
    recording = create(
      :voice_recording,
      call: call,
      status: 'active',
      egress_id: 'EG_aborted',
      bucket: 'recordings'
    )
    allow(Voice::Livekit::EgressService).to receive(:stop).and_return(
      {
        'status' => 'failed',
        'code' => '412',
        'error' => 'egress with status EGRESS_ABORTED cannot be stopped'
      }
    )
    allow(Voice::Livekit::EgressService).to receive(:fetch).and_return(
      {
        'status' => 'failed',
        'code' => '404',
        'error' => 'egress not found'
      }
    )

    result = described_class.perform(call: call)

    expect(result).to include('status' => 'failed', 'code' => '412')
    expect(result['reconcile_result']).to include('status' => 'failed', 'code' => '404')
    expect(recording.reload).to have_attributes(
      status: 'failed',
      error_message: 'egress with status EGRESS_ABORTED cannot be stopped'
    )
    expect(message.reload.content_attributes.dig('data', 'recording')).to include(
      'id' => recording.id,
      'status' => 'failed'
    )
  end

  it 'marks the recording failed when StopEgress cannot find the egress' do
    message = create(:message, account: call.account, inbox: call.inbox, conversation: call.conversation, content_type: 'voice_call')
    call.update!(message: message)
    recording = create(
      :voice_recording,
      call: call,
      status: 'active',
      egress_id: 'EG_missing',
      bucket: 'recordings'
    )
    allow(Voice::Livekit::EgressService).to receive(:stop).and_return(
      {
        'status' => 'failed',
        'code' => '404',
        'error' => 'object cannot be found'
      }
    )
    allow(Voice::Livekit::EgressService).to receive(:fetch)

    result = described_class.perform(call: call)

    expect(result).to include('status' => 'failed', 'code' => '404')
    expect(Voice::Livekit::EgressService).not_to have_received(:fetch)
    expect(recording.reload).to have_attributes(
      status: 'failed',
      error_message: 'object cannot be found'
    )
    expect(message.reload.content_attributes.dig('data', 'recording')).to include(
      'id' => recording.id,
      'status' => 'failed'
    )
  end

  def completed_lookup_result
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
  end

  def aborted_lookup_result
    {
      'status' => 'ok',
      'egress_id' => 'EG_aborted',
      'egress_status' => 'EGRESS_ABORTED',
      'response' => {
        'egress_id' => 'EG_aborted',
        'status' => 'EGRESS_ABORTED',
        'ended_at' => '1781295582063947754',
        'error' => 'room closed before media was written'
      }
    }
  end
end
