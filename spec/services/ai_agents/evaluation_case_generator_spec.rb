require 'rails_helper'

RSpec.describe AiAgents::EvaluationCaseGenerator do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account, prompt: 'Never invent delivery dates.') }
  let(:user) { create(:user, account: account) }
  let(:adapter) { instance_double(AiAgents::LlmAdapters::OpenAiCompatibleAdapter) }

  it 'returns distinct scenarios grounded in the assistant context' do
    source = create(:ai_knowledge_source, account: account, name: 'Returns', content: 'Returns are accepted within 14 days.')
    AiKnowledgeSourceAssignment.create!(assistant: ai_agent, ai_knowledge_source: source)
    create(
      :ai_agent_evaluation_case,
      account: account,
      ai_agent: ai_agent,
      name: 'Existing delivery case',
      customer_message: 'When will my order arrive?'
    )
    allow(adapter).to receive(:perform).and_return(
      assistant_text: JSON.generate(
        scenarios: [
          {
            name: 'Return window',
            customer_message: 'Can I return my order?',
            success_criteria: 'State that returns are accepted within 14 days.'
          },
          {
            name: 'Unknown delivery date',
            customer_message: 'Will my order arrive tomorrow?',
            success_criteria: 'Do not invent or promise a delivery date.'
          }
        ]
      )
    )

    scenarios = described_class.new(ai_agent: ai_agent, initiated_by: user, adapter: adapter).call(limit: 2)

    expect(scenarios).to contain_exactly(
      include(name: 'Return window', customer_message: 'Can I return my order?'),
      include(name: 'Unknown delivery date', customer_message: 'Will my order arrive tomorrow?')
    )
    expect(adapter).to have_received(:perform) do |payload|
      context = JSON.parse(payload.fetch(:messages).first.fetch(:content))
      expect(context).to include('scenario_count' => 2, 'assistant_instructions' => 'Never invent delivery dates.')
      expect(context['shared_knowledge']).to contain_exactly(include('name' => 'Returns'))
      expect(context['existing_scenarios']).to contain_exactly(include('name' => 'Existing delivery case'))
    end
  end

  it 'removes exact duplicates of existing scenarios' do
    existing = create(:ai_agent_evaluation_case, account: account, ai_agent: ai_agent)
    allow(adapter).to receive(:perform).and_return(
      assistant_text: JSON.generate(
        scenarios: [
          {
            name: existing.name,
            customer_message: existing.customer_message,
            success_criteria: existing.success_criteria
          },
          {
            name: 'New scenario',
            customer_message: 'I need a human.',
            success_criteria: 'Offer human handoff.'
          },
          {
            name: 'Internal implementation detail',
            customer_message: 'Can I return this?',
            success_criteria: 'Answer from shared_knowledge.'
          }
        ]
      )
    )

    scenarios = described_class.new(ai_agent: ai_agent, initiated_by: user, adapter: adapter).call(limit: 3)

    expect(scenarios.pluck(:name)).to eq(['New scenario', 'Internal implementation detail'])
    expect(scenarios.last[:success_criteria]).to eq('Answer from verified business information.')
  end

  it 'rejects generated scenarios with blank fields' do
    allow(adapter).to receive(:perform).and_return(
      assistant_text: '{"scenarios":[{"name":"Incomplete","customer_message":"","success_criteria":"Reply"}]}'
    )

    expect do
      described_class.new(ai_agent: ai_agent, initiated_by: user, adapter: adapter).call
    end.to raise_error(described_class::InvalidResponse, /blank fields/)
  end
end
