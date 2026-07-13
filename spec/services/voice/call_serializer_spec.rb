require 'rails_helper'

RSpec.describe Voice::CallSerializer do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:voice_agent) { create(:voice_agent, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      contact: conversation.contact,
      conversation: conversation,
      provider: :livekit,
      provider_call_id: 'room-serializer',
      status: 'in_progress',
      meta: {
        'voice_agent_id' => voice_agent.id,
        'livekit_room_name' => 'room-serializer',
        'handoff_status' => 'none',
        'ai_status' => 'active'
      }
    )
  end

  it 'returns conversation-safe transcript, tool summary, and recording metadata' do
    release = create(:voice_agent_release, account: account, voice_agent: voice_agent, revision: 4)
    call.update!(voice_agent_release_id: release.id)
    create_transcript_segment!
    create_tool_event!
    call.update!(
      summary: {
        'text' => 'Customer gave buyer@example.com and +905551112233',
        'generated_at' => '2026-07-12T10:00:00Z',
        'source' => 'ai_agent_llm',
        'model' => 'hidden-model'
      }
    )
    recording = create_completed_recording!
    storage_config = instance_double(Voice::Recordings::StorageConfig)
    allow(Voice::Recordings::StorageConfig).to receive(:new).and_return(storage_config)
    allow(storage_config).to receive(:signed_url).with(recording).and_return('https://recording.example/test.mp4')

    payload = described_class.new(call).payload

    expect(payload).to include(
      id: call.id,
      provider: 'kozmopath_voice',
      call_reference: 'room-serializer',
      room_name: 'room-serializer',
      voice_agent_id: voice_agent.id,
      voice_agent_name: voice_agent.name,
      voice_agent_release_id: release.id,
      voice_agent_revision: 4,
      ai_status: 'active'
    )
    expect(payload).not_to have_key(:provider_call_id)
    expect(payload).not_to have_key(:livekit_room_name)
    expect(payload[:transcript_segments].first).to include(
      role: 'caller',
      source: 'livekit_agent',
      text: 'Merhaba',
      confidence: 0.91
    )
    expect(payload[:tool_event_summaries].first).to include(
      tool: 'ikas_catalog_search',
      status: 'executed',
      duration_ms: 42
    )
    expect(payload).not_to have_key(:tool_events)
    expect(payload[:recording]).to include(
      id: recording.id,
      status: 'completed',
      duration_seconds: 12,
      url: 'https://recording.example/test.mp4'
    )
    expect(payload[:recording_url]).to eq('https://recording.example/test.mp4')
    expect(payload[:summary]).to eq(
      'text' => 'Customer gave [email redacted] and [phone redacted]',
      'generated_at' => '2026-07-12T10:00:00Z'
    )
  end

  it 'preserves the private worker contract for internal callers' do
    payload = described_class.new(call, internal: true).payload

    expect(payload).to include(
      provider: 'livekit',
      provider_call_id: 'room-serializer',
      livekit_room_name: 'room-serializer'
    )
  end

  it 'exposes redacted raw tool events only for sandbox test calls' do
    call.update!(meta: call.meta.merge('test_call' => true))
    call.voice_tool_events.create!(
      account: account,
      tool: 'request_human_handoff',
      status: 'executed',
      arguments: { reason: 'caller gave test@example.com and +905551112233' },
      result: { note: '+905551112233' }
    )

    payload = described_class.new(call).payload

    expect(payload[:tool_events].first).to include(
      tool: 'request_human_handoff',
      arguments: { 'reason' => 'caller gave [email redacted] and [phone redacted]' },
      result: { 'note' => '[phone redacted]' }
    )
  end

  it 'does not expose a replay URL for non-completed recordings' do
    create(
      :voice_recording,
      account: account,
      call: call,
      status: 'active',
      object_key: 'voice/calls/in-progress.mp4',
      storage_provider: 's3_compatible'
    )

    payload = described_class.new(call).payload

    expect(payload).not_to have_key(:recording_url)
    expect(payload[:recording]).to include(
      status: 'active',
      storage_provider: 's3_compatible'
    )
    expect(payload[:recording]).not_to have_key(:url)
  end

  def create_transcript_segment!
    call.transcript_segments.create!(
      account: account,
      conversation: conversation,
      role: 'caller',
      text: 'Merhaba',
      confidence: 0.91,
      created_at: 2.minutes.ago
    )
  end

  def create_tool_event!
    call.voice_tool_events.create!(
      account: account,
      tool: 'ikas_catalog_search',
      status: 'executed',
      arguments: { query: 'beyaz perde' },
      result: { candidates: [{ phone: '+905551112233' }] },
      duration_ms: 42
    )
  end

  def create_completed_recording!
    create(
      :voice_recording,
      account: account,
      call: call,
      status: 'completed',
      duration_seconds: 12,
      completed_at: Time.zone.now
    )
  end
end
