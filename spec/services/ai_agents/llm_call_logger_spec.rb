require 'rails_helper'

RSpec.describe AiAgents::LlmCallLogger do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:trigger_message) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact)
  end
  let(:logger) do
    described_class.new(ai_agent: ai_agent, account: account, conversation: conversation, trigger_message: trigger_message, mode: :live)
  end

  it 'persists request messages and response metadata for an LLM turn' do
    logger.call(
      step: 'initial',
      model: 'openai/gpt-5.1',
      request_messages: [{ role: 'user', content: 'beyaz olanin linki var mi' }],
      request_tools: [{ type: 'function', function: { name: 'ikas_catalog_search' } }],
      request_options: { max_tokens: 4_096, ignored_secret: 'do-not-store' },
      status: 'succeeded',
      response: { assistant_text: nil, tool_calls: [{ name: 'ikas_catalog_search' }], finish_reason: 'tool_calls', usage: { 'total_tokens' => 42 } },
      duration_ms: 25
    )

    llm_call = AiAgentLlmCall.last
    expect(llm_call).to have_attributes(account: account, ai_agent: ai_agent, conversation: conversation, message: trigger_message,
                                        step: 'initial', mode: 'live', status: 'succeeded', model: 'openai/gpt-5.1')
    expect(llm_call.request_messages).to eq([{ 'role' => 'user', 'content' => 'beyaz olanin linki var mi' }])
    expect(llm_call.request_tool_names).to eq(['ikas_catalog_search'])
    expect(llm_call.response).to eq('assistant_text' => nil, 'tool_calls' => [{ 'name' => 'ikas_catalog_search' }],
                                    'finish_reason' => 'tool_calls', 'request_options' => { 'max_tokens' => 4_096 })
    expect(llm_call.usage).to eq('total_tokens' => 42)
  end

  it 'persists failures without raising from the logger' do
    error = RuntimeError.new('timeout')

    logger.call(
      step: 'initial',
      model: 'openai/gpt-5.1',
      request_messages: [{ role: 'user', content: 'Hello' }],
      request_tools: [],
      status: 'failed',
      error: error,
      duration_ms: 1
    )

    llm_call = AiAgentLlmCall.last
    expect(llm_call).to have_attributes(status: 'failed', error_code: 'RuntimeError', error_message: 'timeout')
  end
end
