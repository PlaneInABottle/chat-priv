require 'rails_helper'

RSpec.describe AiAgents::LearningSuggestionGenerator do
  let(:ai_agent) { create(:ai_agent, prompt: 'Never invent policy details.') }
  let(:adapter) { instance_double(AiAgents::LlmAdapters::OpenAiCompatibleAdapter) }

  it 'returns reusable guidance from valid provider JSON' do
    allow(adapter).to receive(:perform).and_return(
      assistant_text: JSON.generate(
        useful: true,
        destination: 'instructions',
        target_section: 'rules',
        source_name: nil,
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
      destination: 'instructions',
      target_section: 'rules',
      instruction: 'Do not promise an exact delivery date.'
    )
  end

  it 'returns reusable business facts as shared knowledge' do
    allow(adapter).to receive(:perform).and_return(
      assistant_text: JSON.generate(
        useful: true,
        destination: 'knowledge',
        target_section: nil,
        source_name: 'Returns policy',
        instruction: 'Returns are accepted within 14 days of delivery.',
        reason: 'The human answer states a reusable return policy.'
      )
    )

    result = described_class.new(ai_agent: ai_agent, adapter: adapter).call(
      customer_message: 'Can I return this?',
      human_answer: 'Returns are accepted within 14 days of delivery.'
    )

    expect(result).to have_attributes(
      useful: true,
      destination: 'knowledge',
      source_name: 'Returns policy',
      target_section: nil,
      instruction: 'Returns are accepted within 14 days of delivery.'
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

  it 'includes selected shared knowledge so duplicate guidance can be rejected' do
    source = create(:ai_knowledge_source, account: ai_agent.account, name: 'Returns', content: 'Returns are accepted within 14 days.')
    AiKnowledgeSourceAssignment.create!(assistant: ai_agent, ai_knowledge_source: source)
    allow(adapter).to receive(:perform).and_return(
      assistant_text: '{"useful":false,"target_section":null,"instruction":null,"reason":"Already covered."}'
    )

    described_class.new(ai_agent: ai_agent, adapter: adapter).call(
      customer_message: 'Can I return this?',
      human_answer: 'Returns are accepted within 14 days.'
    )

    expect(adapter).to have_received(:perform) do |payload|
      learning_data = JSON.parse(payload.fetch(:messages).first.fetch(:content))
      expect(learning_data['existing_knowledge']).to contain_exactly(
        'name' => 'Returns',
        'content' => 'Returns are accepted within 14 days.'
      )
    end
  end

  it 'rejects an unsupported target section' do
    allow(adapter).to receive(:perform).and_return(
      assistant_text: JSON.generate(
        useful: true,
        destination: 'instructions',
        target_section: 'identity',
        source_name: nil,
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
