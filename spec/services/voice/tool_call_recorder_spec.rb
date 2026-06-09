require 'rails_helper'

RSpec.describe Voice::ToolCallRecorder do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:call) { Voice::TestCallBuilder.perform!(account: account, inbox: inbox) }

  before do
    allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return({ 'status' => 'skipped' })
    allow(Voice::CallBroadcaster).to receive(:tool_event)
  end

  it 'persists sanitized tool events in the voice_tool_events table' do
    event = described_class.perform!(
      call: call,
      tool: 'request_human_handoff',
      status: 'executed',
      arguments: { reason: 'caller gave test@example.com and +905551112233' },
      result: { tool_status: 'ok' },
      duration_ms: 42
    )

    expect(event).to be_persisted
    expect(event).to have_attributes(
      tool: 'request_human_handoff',
      status: 'executed',
      duration_ms: 42,
      result: { 'tool_status' => 'ok' }
    )
    expect(event.arguments['reason']).to eq('caller gave [email redacted] and [phone redacted]')
    expect(call.voice_tool_events.order(:created_at)).to eq([event])
    expect(Voice::CallBroadcaster).to have_received(:tool_event).with(call, event)
  end

  it 'is idempotent when the same external_id is posted again' do
    first = described_class.perform!(
      call: call,
      tool: 'request_human_handoff',
      status: 'executed',
      arguments: { reason: 'same request' },
      result: { tool_status: 'ok' },
      duration_ms: 42,
      external_id: 'tool-call-1'
    )

    second = described_class.perform!(
      call: call,
      tool: 'request_human_handoff',
      status: 'executed',
      arguments: { reason: 'same request' },
      result: { tool_status: 'ok' },
      duration_ms: 42,
      external_id: 'tool-call-1'
    )

    expect(second).to eq(first)
    expect(call.voice_tool_events.count).to eq(1)
  end
end
