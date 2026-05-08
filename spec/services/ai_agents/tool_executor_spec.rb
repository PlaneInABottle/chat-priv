require 'rails_helper'

RSpec.describe AiAgents::ToolExecutor do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, :with_human_handoff_tool, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:trigger_message) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact)
  end
  let(:executor) do
    described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :test,
      context: { conversation: conversation, trigger_message: trigger_message }
    )
  end

  def handoff_args
    { reason: 'Need help', customer_message: 'A human will take over.', internal_note: 'Escalate' }
  end

  def tool_call(name: 'human_handoff', arguments: {})
    { id: 'call_1', name: name, arguments: arguments.to_json }
  end

  def stub_handoff_service(result: nil, error: nil)
    service = instance_double(AiAgents::Tools::HumanHandoffService)
    allow(AiAgents::Tools::HumanHandoffService).to receive(:new).and_return(service)
    return allow(service).to receive(:call).and_raise(error) if error

    allow(service).to receive(:call).and_return(result)
  end

  it 'logs unknown tool rejections' do
    result = executor.execute(tool_call(name: 'unknown_tool'))

    expect(result.status).to eq('rejected')
    expect(AiAgentToolExecution.last).to have_attributes(tool_key: 'unknown_tool', status: 'rejected', error_code: 'unknown_tool')
  end

  it 'logs disabled tool rejections' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => [] } })

    result = executor.execute(tool_call)

    expect(result.status).to eq('rejected')
    expect(AiAgentToolExecution.last.error_code).to eq('tool_not_enabled')
  end

  it 'logs invalid JSON arguments as an empty hash' do
    result = executor.execute({ id: 'call_1', name: 'human_handoff', arguments: '{' })

    expect(result.status).to eq('rejected')
    expect(AiAgentToolExecution.last).to have_attributes(error_code: 'invalid_tool_arguments', arguments: {})
  end

  it 'logs successful service execution without changing the tool event shape' do
    result = executor.execute(tool_call(arguments: handoff_args))

    expect(result.status).to eq('executed')
    expect(result.tool_event.keys).to match_array(%w[tool status tool_call_id terminal args result])
    expect(AiAgentToolExecution.last).to have_attributes(status: 'executed', tool_key: 'human_handoff')
  end

  it 'logs service error results' do
    stub_handoff_service(result: { status: 'error', error_code: 'handoff_failed', raw_response: 'secret' })

    result = executor.execute(tool_call(arguments: handoff_args))

    expect(result.status).to eq('error')
    expect(AiAgentToolExecution.last).to have_attributes(status: 'error', error_code: 'handoff_failed',
                                                         result: { 'status' => 'error', 'error_code' => 'handoff_failed' })
  end

  it 'logs service exceptions as rejected tool exceptions' do
    stub_handoff_service(error: StandardError.new('boom'))

    result = executor.execute(tool_call(arguments: handoff_args))

    expect(result.status).to eq('rejected')
    expect(AiAgentToolExecution.last).to have_attributes(status: 'rejected', error_code: 'tool_exception')
  end

  it 'does not change executor results when logging fails' do
    allow(AiAgentToolExecution).to receive(:create!).and_raise(StandardError, 'log failed')

    result = executor.execute(tool_call(arguments: handoff_args))

    expect(result.status).to eq('executed')
  end
end
