require 'rails_helper'

RSpec.describe AiAgents::ToolExecutionLogger do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:trigger_message) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact)
  end
  let(:definition) { AiAgents::ToolRegistry.find('human_handoff') }
  let(:logger) do
    described_class.new(ai_agent: ai_agent, account: account, conversation: conversation, trigger_message: trigger_message, mode: :test)
  end

  it 'persists a sanitized execution row' do
    logger.call(
      tool_call: { id: 'call_1', name: 'human_handoff' },
      definition: definition,
      status: 'executed',
      payload: {
        tool_result: { status: 'ok', raw_response: 'secret' },
        args: { 'reason' => 'Need help' },
        duration_ms: 12
      }
    )

    execution = AiAgentToolExecution.last
    expect(execution).to have_attributes(account: account, ai_agent: ai_agent, conversation: conversation, message: trigger_message)
    expect(execution.result).to eq('status' => 'ok')
  end

  it 'persists rejected errors without requiring conversation or message' do
    described_class.new(ai_agent: ai_agent, account: account, conversation: nil, trigger_message: nil, mode: :live).call(
      tool_call: { id: 'call_2', name: 'missing_tool' },
      definition: nil,
      status: 'rejected',
      payload: {
        tool_result: { status: 'error', error_code: 'unknown_tool', error_message: 'Tool execution was rejected.' },
        args: {},
        duration_ms: 1
      }
    )

    execution = AiAgentToolExecution.last
    expect(execution.tool_key).to eq('missing_tool')
    expect(execution.error_code).to eq('unknown_tool')
  end

  it 'redacts customer identifiers from persisted arguments, results, and errors' do
    logger.call(
      tool_call: { id: 'call_3', name: 'human_handoff' },
      definition: definition,
      status: 'error',
      payload: {
        tool_result: {
          status: 'error',
          error_message: 'Failed for buyer@example.com',
          customer_message: 'Call +90 555 123 45 67'
        },
        args: { 'email' => 'buyer@example.com', 'phone' => '+90 555 123 45 67' }
      }
    )

    execution = AiAgentToolExecution.last
    persisted_payload = [execution.arguments, execution.result, execution.error_message].to_json
    expect(persisted_payload).to include('[email redacted]', '[phone redacted]')
    expect(persisted_payload).not_to include('buyer@example.com', '+90 555 123 45 67')
  end
end
