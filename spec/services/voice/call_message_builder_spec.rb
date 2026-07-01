require 'rails_helper'

RSpec.describe Voice::CallMessageBuilder do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
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
      provider_call_id: 'room-message-builder',
      status: 'in_progress',
      meta: {
        'livekit_room_name' => 'room-message-builder',
        'handoff_status' => 'requested',
        'ai_status' => 'active'
      }
    )
  end

  it 'creates a voice call message with LiveKit call metadata' do
    message = described_class.new(call).perform!

    expect(message).to be_persisted
    expect(message.content_type).to eq('voice_call')
    expect(message.content_attributes['data']).to include(
      'call_id' => call.id,
      'call_sid' => 'room-message-builder',
      'call_source' => 'livekit',
      'status' => 'in-progress',
      'handoff_status' => 'requested',
      'ai_status' => 'active'
    )
  end

  it 'refreshes terminal status and recording metadata without signed URLs' do
    message = described_class.new(call).perform!
    call.update!(
      message_id: message.id,
      status: 'completed',
      duration_seconds: 64,
      ai_status: 'silent',
      summary: { 'text' => 'Customer gave buyer@example.com and +905551112233' }
    )
    recording = create(:voice_recording, account: account, call: call, status: 'completed', duration_seconds: 61)

    described_class.new(call).update_status!(status: call.status, duration_seconds: call.duration_seconds)

    data = message.reload.content_attributes['data']
    expect(data).to include(
      'status' => 'completed',
      'duration_seconds' => 64,
      'ai_status' => 'silent'
    )
    expect(data['recording']).to include(
      'id' => recording.id,
      'status' => 'completed',
      'duration_seconds' => 61
    )
    expect(data['recording']).not_to have_key('url')
    expect(data['summary']).to eq('text' => 'Customer gave [email redacted] and [phone redacted]')
  end
end
