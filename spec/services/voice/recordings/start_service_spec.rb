require 'rails_helper'

RSpec.describe Voice::Recordings::StartService do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:setting) { create(:voice_inbox_setting, account: account, inbox: inbox, recording_enabled: true) }

  before do
    allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return({ 'status' => 'skipped' })
    allow(Voice::Livekit::EgressService).to receive(:start_room_composite).and_return(
      {
        'status' => 'ok',
        'egress_id' => 'EG_started',
        'response' => { 'egress_id' => 'EG_started', 'status' => 'EGRESS_STARTING' }
      }
    )
  end

  it 'skips sandbox test calls' do
    call = Voice::TestCallBuilder.perform!(account: account, inbox: inbox)

    result = with_modified_env(recording_env) do
      described_class.perform(call: call)
    end

    expect(result).to eq('status' => 'skipped', 'reason' => 'test_call')
    expect(Voice::Livekit::EgressService).not_to have_received(:start_room_composite)
    expect(call.voice_recordings).to be_empty
  end

  it 'starts a recording for real LiveKit calls with recording enabled' do
    call = real_livekit_call

    result = with_modified_env(recording_env) do
      described_class.perform(call: call)
    end

    recording = call.voice_recordings.first
    expect(result).to include('status' => 'started', 'egress_id' => 'EG_started')
    expect(recording).to have_attributes(
      status: 'active',
      egress_id: 'EG_started',
      bucket: 'voice-recordings-test',
      storage_provider: 's3_compatible',
      content_type: 'audio/mp4'
    )
    expect(recording.object_key).to include("account-#{account.id}/call-#{call.id}")
    expect(Voice::Livekit::EgressService).to have_received(:start_room_composite).with(call: call, recording: recording)
  end

  it 'skips when the inbox setting disables recording' do
    setting.update!(recording_enabled: false)
    call = real_livekit_call

    result = with_modified_env(recording_env) do
      described_class.perform(call: call)
    end

    expect(result).to eq('status' => 'skipped', 'reason' => 'recording_disabled')
    expect(call.voice_recordings).to be_empty
  end

  def real_livekit_call
    Voice::InboundCallBuilder.perform!(
      inbox: inbox,
      from_number: '+905551112233',
      call_sid: "room-#{SecureRandom.hex(4)}",
      provider: :livekit,
      extra_meta: {
        'livekit_room_name' => "room-#{SecureRandom.hex(4)}",
        'voice_inbox_setting_id' => setting.id,
        'handoff_status' => 'none',
        'ai_status' => 'waiting'
      }
    ).tap do |call|
      call.update!(started_at: Time.zone.now, status: 'in_progress')
      call.voice_recordings.delete_all
      allow(Voice::Livekit::EgressService).to receive(:start_room_composite).and_return(
        {
          'status' => 'ok',
          'egress_id' => 'EG_started',
          'response' => { 'egress_id' => 'EG_started', 'status' => 'EGRESS_STARTING' }
        }
      )
    end
  end

  def recording_env
    {
      'VOICE_RECORDING_S3_ACCESS_KEY_ID' => 'access-key',
      'VOICE_RECORDING_S3_SECRET_ACCESS_KEY' => 'secret-key',
      'VOICE_RECORDING_S3_BUCKET' => 'voice-recordings-test'
    }
  end
end
