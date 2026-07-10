require 'rails_helper'

RSpec.describe AiAgents::LearningSuggestionGenerator do
  let(:ai_agent) { create(:ai_agent, prompt: 'Never invent policy details.') }
  let(:adapter) { instance_double(AiAgents::LlmAdapters::OpenAiCompatibleAdapter) }

  it 'returns reusable guidance from valid provider JSON' do
    allow(adapter).to receive(:perform).and_return(
      assistant_text: JSON.generate(
        useful: true,
        target_section: 'rules',
        instruction: 'Do not promise an exact delivery date.',
        reason: 'The human answer establishes a reusable delivery boundary.'
      )
    )

    result = described_class.new(ai_agent: ai_agent, adapter: adapter).call(
      customer_message: 'Will it arrive Tuesday?',
      human_answer: 'Delivery timing depends on the destination.'
    )

    expect(result).to have_attributes(
      useful: true,
      target_section: 'rules',
      instruction: 'Do not promise an exact delivery date.'
    )
  end

  it 'supports a not-useful judgment without an instruction' do
    allow(adapter).to receive(:perform).and_return(
      assistant_text: '{"useful":false,"target_section":null,"instruction":null,"reason":"This is a greeting."}'
    )

    result = described_class.new(ai_agent: ai_agent, adapter: adapter).call(
      customer_message: 'Hello',
      human_answer: 'Hello, how can I help?'
    )

    expect(result).to have_attributes(useful: false, reason: 'This is a greeting.')
  end

  it 'rejects an unsupported target section' do
    allow(adapter).to receive(:perform).and_return(
      assistant_text: JSON.generate(
        useful: true,
        target_section: 'identity',
        instruction: 'Call yourself Alex.',
        reason: 'The answer used this name.'
      )
    )

    expect do
      described_class.new(ai_agent: ai_agent, adapter: adapter).call(
        customer_message: 'Who are you?',
        human_answer: 'I am Alex.'
      )
    end.to raise_error(described_class::InvalidResponse, /invalid target section/)
  end
end
