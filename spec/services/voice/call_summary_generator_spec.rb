require 'rails_helper'

RSpec.describe Voice::CallSummaryGenerator do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :livekit,
      status: 'completed'
    )
  end

  before do
    allow(AiAgents::Settings).to receive(:llm_api_key).and_return('test-key')
    allow(AiAgents::Settings).to receive(:llm_endpoint).and_return('https://llm.example.test/v1/chat/completions')
    allow(AiAgents::Settings).to receive(:llm_timeout_seconds).and_return(5)
  end

  it 'stores a redacted summary from the configured AI-agent LLM' do
    call.transcript_segments.create!(
      account: account,
      conversation: conversation,
      role: 'caller',
      text: 'My email is buyer@example.com and my phone is +905551112233'
    )
    http = instance_double(Net::HTTP)
    response = instance_double(
      Net::HTTPResponse,
      body: {
        choices: [
          { message: { content: 'Customer asked for order help. Email buyer@example.com, phone +905551112233.' } }
        ]
      }.to_json
    )
    allow(Net::HTTP).to receive(:new).with('llm.example.test', 443).and_return(http)
    allow(http).to receive(:use_ssl=).with(true)
    allow(http).to receive(:read_timeout=).with(5)
    allow(http).to receive(:request).and_return(response)

    described_class.perform(call: call)

    expect(call.reload.summary).to include(
      'text' => 'Customer asked for order help. Email [email redacted], phone [phone redacted].',
      'source' => 'ai_agent_llm',
      'model' => account.ai_agent_model
    )
    expect(call.summary['generated_at']).to be_present
  end

  it 'skips calls without an LLM API key' do
    allow(AiAgents::Settings).to receive(:llm_api_key).and_return(nil)
    call.transcript_segments.create!(
      account: account,
      conversation: conversation,
      role: 'caller',
      text: 'I need help'
    )

    described_class.perform(call: call)

    expect(call.reload.summary).to be_blank
  end

  it 'skips sandbox test calls' do
    call.update!(meta: { 'test_call' => true })
    call.transcript_segments.create!(
      account: account,
      conversation: conversation,
      role: 'caller',
      text: 'I need help'
    )

    described_class.perform(call: call)

    expect(call.reload.summary).to be_blank
  end
end
