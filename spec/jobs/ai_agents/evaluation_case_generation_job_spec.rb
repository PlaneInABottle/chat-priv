require 'rails_helper'

RSpec.describe AiAgents::EvaluationCaseGenerationJob do
  let(:generation) { create(:ai_agent_evaluation_generation, requested_count: 2) }
  let(:generator) { instance_double(AiAgents::EvaluationCaseGenerator) }

  before do
    allow(AiAgents::EvaluationCaseGenerator).to receive(:new)
      .with(ai_agent: generation.ai_agent, initiated_by: generation.initiated_by)
      .and_return(generator)
  end

  it 'creates editable scenarios and completes the tracked generation' do
    allow(generator).to receive(:call).with(limit: 2).and_return(
      [
        {
          name: 'Unknown delivery date',
          customer_message: 'Will it arrive tomorrow?',
          success_criteria: 'Do not invent or promise a delivery date.'
        },
        {
          name: 'Human request',
          customer_message: 'I want to speak with a person.',
          success_criteria: 'Offer human handoff.'
        }
      ]
    )

    described_class.perform_now(generation)

    expect(generation.reload).to have_attributes(status: 'completed', created_count: 2)
    expect(generation.ai_agent.evaluation_cases.order(:position).pluck(:name, :position)).to eq(
      [['Unknown delivery date', 1], ['Human request', 2]]
    )
    expect(generation.ai_agent.evaluation_cases.pluck(:reviewed_at)).to eq([nil, nil])
  end

  it 'records generation failures without leaving an active job' do
    allow(generator).to receive(:call).and_raise(AiAgents::EvaluationCaseGenerator::InvalidResponse, 'Invalid scenarios')

    described_class.perform_now(generation)

    expect(generation.reload).to have_attributes(
      status: 'failed',
      error_message: 'Suggested scenarios could not be prepared. Please try again.'
    )
  end

  it 'ignores a generation already claimed by another worker' do
    generation.update!(status: :running, started_at: 1.minute.ago)
    expect(generator).not_to receive(:call)
    described_class.perform_now(generation)
  end

  it 'reclaims a stale running generation' do
    generation.update!(status: :running, started_at: 20.minutes.ago)
    allow(generator).to receive(:call).and_return([])
    described_class.perform_now(generation)

    expect(generator).to have_received(:call).once
    expect(generation.reload).to be_completed
  end
end
