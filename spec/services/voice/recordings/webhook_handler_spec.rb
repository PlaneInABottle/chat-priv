require 'rails_helper'

RSpec.describe Voice::Recordings::WebhookHandler do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      contact: conversation.contact,
      conversation: conversation,
      provider: :livekit,
      provider_call_id: 'room-1',
      status: 'completed'
    )
  end
  let!(:message) { Voice::CallMessageBuilder.new(call).perform! }
  let!(:recording) do
    create(
      :voice_recording,
      account: account,
      call: call,
      status: 'active',
      egress_id: 'EG_test',
      bucket: 'recordings',
      object_key: 'voice-recordings/account-1/call-1/original.mp4'
    )
  end

  before do
    call.update!(message_id: message.id)
    allow(Voice::CallBroadcaster).to receive(:safe_call_status_changed)
  end

  it 'marks completed egress and refreshes the message recording metadata' do
    result = described_class.perform!(payload: completed_payload)

    expect(result).to include('status' => 'completed', 'recording_id' => recording.id)
    expect(recording.reload).to have_attributes(
      status: 'completed',
      duration_seconds: 12,
      object_key: 'voice-recordings/account-1/call-1/final.mp4',
      error_message: nil
    )
    expect(call.message.reload.content_attributes.dig('data', 'recording')).to include(
      'id' => recording.id,
      'status' => 'completed',
      'duration_seconds' => 12
    )
    expect(call.message.content_attributes.dig('data', 'recording')).not_to have_key('url')
    expect(Voice::CallBroadcaster).to have_received(:safe_call_status_changed).with(call)
  end

  it 'keeps the original object key when LiveKit omits file location' do
    described_class.perform!(payload: completed_payload(location: nil))

    expect(recording.reload).to have_attributes(
      status: 'completed',
      object_key: 'voice-recordings/account-1/call-1/original.mp4'
    )
  end

  it 'marks failed egress with the LiveKit error' do
    result = described_class.perform!(
      payload: {
        'event' => 'egress_ended',
        'egressInfo' => {
          'egressId' => 'EG_test',
          'status' => 'EGRESS_FAILED',
          'error' => 'upload failed'
        }
      }
    )

    expect(result).to include('status' => 'failed', 'recording_id' => recording.id)
    expect(recording.reload).to have_attributes(status: 'failed', error_message: 'upload failed')
  end

  it 'is idempotent for replayed completed webhooks' do
    2.times { described_class.perform!(payload: completed_payload) }

    expect(recording.reload).to have_attributes(
      status: 'completed',
      duration_seconds: 12,
      object_key: 'voice-recordings/account-1/call-1/final.mp4'
    )
  end

  it 'does not rewrite terminal recordings from delayed webhooks' do
    recording.update!(
      status: 'failed',
      completed_at: 1.hour.ago,
      error_message: 'previous failure'
    )

    result = described_class.perform!(payload: completed_payload)

    expect(result).to include('status' => 'failed', 'reason' => 'already_terminal')
    expect(recording.reload).to have_attributes(
      status: 'failed',
      error_message: 'previous failure'
    )
  end

  def completed_payload(location: 's3://recordings/voice-recordings/account-1/call-1/final.mp4')
    file_result = { 'duration' => 12_000_000_000 }
    file_result['location'] = location if location
    {
      'event' => 'egress_ended',
      'egressInfo' => {
        'egressId' => 'EG_test',
        'status' => 'EGRESS_COMPLETE',
        'endedAt' => 1_700_000_000_000_000_000,
        'fileResults' => [file_result]
      }
    }
  end
end
