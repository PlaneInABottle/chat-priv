require 'rails_helper'

RSpec.describe Voice::Calls::ActivityEvidence do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      provider: :livekit
    )
  end

  it 'collects transcript, action, error, and latest recording evidence' do
    create_transcript_segment
    create_tool_event('executed')
    create_tool_event('error')
    create(:voice_recording, account: account, call: call, status: 'failed', created_at: 1.minute.ago)
    create(:voice_recording, account: account, call: call, status: 'completed')

    evidence = described_class.new([call]).for(call)

    expect(evidence).to eq(
      transcript_count: 1,
      action_count: 2,
      action_error_count: 1,
      recording_status: 'completed'
    )
  end

  def create_transcript_segment
    CallTranscriptSegment.create!(
      account: account,
      call: call,
      conversation: conversation,
      role: 'caller',
      source: 'livekit_agent',
      text: 'I need help.'
    )
  end

  def create_tool_event(status)
    VoiceToolEvent.create!(
      account: account,
      call: call,
      tool: 'request_human_handoff',
      status: status,
      arguments: {},
      result: {},
      source: 'livekit_agent'
    )
  end
end
