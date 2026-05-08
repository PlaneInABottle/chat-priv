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
  end

  it 'normalizes a text-only response' do
    allow(http).to receive(:request).and_return(double(body: {
      'choices' => [{ 'finish_reason' => 'stop', 'message' => { 'content' => 'Hello' } }],
      'usage' => { 'total_tokens' => 12 }
    }.to_json))

    result = adapter.perform(messages: [{ role: 'user', content: 'Hi' }], tools: [], tool_choice: 'auto')

    expect(result[:assistant_text]).to eq('Hello')
    expect(result[:tool_calls]).to eq([])
    expect(result[:finish_reason]).to eq('stop')
  end

  it 'normalizes a single tool call response' do
    allow(http).to receive(:request).and_return(double(body: {
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
    }.to_json))

    result = adapter.perform(messages: [{ role: 'user', content: 'Hi' }], tools: [], tool_choice: 'auto')

    expect(result[:tool_calls]).to eq([
      { id: 'call_1', type: 'function', name: 'human_handoff', arguments: '{"reason":"Need help","internal_note":"Escalate"}' }
    ])
  end
end
