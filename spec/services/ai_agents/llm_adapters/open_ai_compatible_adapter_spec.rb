require 'rails_helper'

RSpec.describe AiAgents::LlmAdapters::OpenAiCompatibleAdapter do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account, enabled: true) }
  let(:adapter) { described_class.new(ai_agent: ai_agent, account: account) }
  let(:http) { instance_double(Net::HTTP) }
  let(:request) { instance_double(Net::HTTP::Post) }

  before do
    allow(Net::HTTP).to receive(:new).and_return(http)
    allow(http).to receive(:use_ssl=)
    allow(http).to receive(:read_timeout=)
    allow(Net::HTTP::Post).to receive(:new).and_return(request)
    allow(request).to receive(:body=)
    allow(AiAgents::Settings).to receive(:llm_endpoint).and_return('https://example.test/v1/chat/completions')
    allow(AiAgents::Settings).to receive(:llm_api_key).and_return('test-key')
    allow(AiAgents::Settings).to receive(:llm_timeout_seconds).and_return(20)
  end

  it 'normalizes a text-only response' do
    response_payload = {
      'choices' => [{ 'finish_reason' => 'stop', 'message' => { 'content' => 'Hello' } }],
      'usage' => { 'total_tokens' => 12 }
    }
    allow(http).to receive(:request).and_return(http_response(response_payload))

    result = adapter.perform(messages: [{ role: 'user', content: 'Hi' }], tools: [], tool_choice: 'auto')

    expect(result[:assistant_text]).to eq('Hello')
    expect(result[:tool_calls]).to eq([])
    expect(result[:finish_reason]).to eq('stop')
  end

  it 'normalizes a single tool call response' do
    response_payload = {
      'choices' => [{
        'finish_reason' => 'tool_calls',
        'message' => {
          'content' => nil,
          'tool_calls' => [{
            'id' => 'call_1',
            'type' => 'function',
            'function' => { 'name' => 'human_handoff', 'arguments' => '{"reason":"Need help","internal_note":"Escalate"}' }
          }]
        }
      }]
    }
    allow(http).to receive(:request).and_return(http_response(response_payload))

    result = adapter.perform(messages: [{ role: 'user', content: 'Hi' }], tools: [], tool_choice: 'auto')

    expect(result[:tool_calls]).to eq(
      [
        {
          id: 'call_1',
          type: 'function',
          name: 'human_handoff',
          arguments: '{"reason":"Need help","internal_note":"Escalate"}'
        }
      ]
    )
  end

  it 'sends the composed effective system prompt' do
    InstallationConfig.where(name: 'AI_AGENT_GLOBAL_INSTRUCTIONS').first_or_initialize.tap do |config|
      config.value = 'Use Turkish by default.'
      config.locked = false
      config.save!
    end
    ai_agent.update!(prompt: 'Only use verified sources.')
    response_payload = {
      'choices' => [{ 'finish_reason' => 'stop', 'message' => { 'content' => 'Merhaba' } }]
    }
    allow(http).to receive(:request).and_return(http_response(response_payload))

    expect(request).to receive(:body=) do |body|
      system_message = JSON.parse(body).fetch('messages').first
      expect(system_message.fetch('content')).to include('Use Turkish by default.', 'Only use verified sources.')
    end

    adapter.perform(messages: [{ role: 'user', content: 'Hi' }], tools: [], tool_choice: 'auto')
  end

  it 'omits tool fields when no tools are available' do
    response_payload = {
      'choices' => [{ 'finish_reason' => 'stop', 'message' => { 'content' => 'Merhaba' } }]
    }
    allow(http).to receive(:request).and_return(http_response(response_payload))

    expect(request).to receive(:body=) do |body|
      payload = JSON.parse(body)
      expect(payload).not_to have_key('tools')
      expect(payload).not_to have_key('tool_choice')
    end

    adapter.perform(messages: [{ role: 'user', content: 'Hi' }], tools: [], tool_choice: 'auto')
  end

  it 'sends task-specific generation options without changing defaults' do
    configured_adapter = described_class.new(
      ai_agent: ai_agent,
      account: account,
      llm_options: {
        max_tokens: 4_096,
        temperature: 0.1,
        response_format: { type: 'json_object' }
      }
    )
    response_payload = {
      'choices' => [{ 'finish_reason' => 'stop', 'message' => { 'content' => '{"ok":true}' } }]
    }
    allow(http).to receive(:request).and_return(http_response(response_payload))

    expect(request).to receive(:body=) do |body|
      payload = JSON.parse(body)
      expect(payload).to include(
        'max_tokens' => 4_096,
        'temperature' => 0.1,
        'response_format' => { 'type' => 'json_object' }
      )
    end

    configured_adapter.perform(messages: [{ role: 'user', content: 'Return JSON' }], tools: [], tool_choice: 'auto')
  end

  it 'does not stringify nil assistant content for tool call messages' do
    response_payload = {
      'choices' => [{ 'finish_reason' => 'stop', 'message' => { 'content' => 'Done' } }]
    }
    allow(http).to receive(:request).and_return(http_response(response_payload))

    expect(request).to receive(:body=) do |body|
      assistant_message = JSON.parse(body).fetch('messages').find { |message| message['role'] == 'assistant' }
      expect(assistant_message).to include('tool_calls')
      expect(assistant_message).not_to have_key('content')
    end

    adapter.perform(
      messages: [
        {
          role: 'assistant',
          content: nil,
          tool_calls: [{ id: 'call_1', type: 'function', function: { name: 'ikas_catalog_search', arguments: '{}' } }]
        }
      ],
      tools: [],
      tool_choice: 'auto'
    )
  end

  def http_response(payload)
    instance_double(Net::HTTPResponse, body: payload.to_json)
  end
end
