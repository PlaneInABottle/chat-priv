require 'rails_helper'

RSpec.describe AiAgents::EvaluationJudge do
  let(:ai_agent) { create(:ai_agent) }
  let(:adapter) { instance_double(AiAgents::LlmAdapters::OpenAiCompatibleAdapter) }

  it 'returns the provider judgment from valid JSON' do
    allow(adapter).to receive(:perform).and_return(
      assistant_text: '{"passed":true,"reason":"The answer avoids an exact promise."}'
    )

    result = described_class.new(ai_agent: ai_agent, adapter: adapter).call(
      customer_message: 'When will it arrive?',
      success_criteria: 'Do not promise an exact date.',
      assistant_response: 'Delivery timing depends on your location.'
    )

    expect(result).to have_attributes(passed: true, reason: 'The answer avoids an exact promise.')
  end

  it 'accepts a fenced JSON response' do
    allow(adapter).to receive(:perform).and_return(
      assistant_text: "```json\n{\"passed\":false,\"reason\":\"It promises Tuesday.\"}\n```"
    )

    result = described_class.new(ai_agent: ai_agent, adapter: adapter).call(
      customer_message: 'When will it arrive?',
      success_criteria: 'Do not promise an exact date.',
      assistant_response: 'It will arrive Tuesday.'
    )

    expect(result).to have_attributes(passed: false, reason: 'It promises Tuesday.')
  end

  it 'rejects malformed provider output' do
    allow(adapter).to receive(:perform).and_return(assistant_text: 'PASS')

    expect do
      described_class.new(ai_agent: ai_agent, adapter: adapter).call(
        customer_message: 'Hello',
        success_criteria: 'Reply politely.',
        assistant_response: 'Hello.'
      )
    end.to raise_error(AiAgents::EvaluationJudge::InvalidResponse, /valid JSON/)
  end
end
