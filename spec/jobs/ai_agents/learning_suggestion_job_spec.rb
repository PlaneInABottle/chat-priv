require 'rails_helper'

RSpec.describe AiAgents::LearningSuggestionJob do
  it 'persists the proposed shared knowledge destination for review' do
    suggestion = create(:ai_agent_learning_suggestion)
    generator = instance_double(AiAgents::LearningSuggestionGenerator)
    allow(AiAgents::LearningSuggestionGenerator).to receive(:new).and_return(generator)
    allow(generator).to receive(:call).and_return(
      AiAgents::LearningSuggestionGenerator::Result.new(
        useful: true,
        destination: 'knowledge',
        source_name: 'Returns policy',
        instruction: 'Returns are accepted within 14 days.',
        reason: 'The human answer states a reusable policy.'
      )
    )

    described_class.perform_now(suggestion)

    expect(suggestion.reload).to have_attributes(
      status: 'ready',
      claim_id: nil,
      destination: 'knowledge',
      source_name: 'Returns policy',
      target_section: nil,
      suggested_instruction: 'Returns are accepted within 14 days.'
    )
  end

  it 'leaves a fresh analysis to the worker that claimed it' do
    suggestion = create(:ai_agent_learning_suggestion, status: :analyzing, updated_at: 1.minute.ago)
    generator = instance_double(AiAgents::LearningSuggestionGenerator)
    allow(AiAgents::LearningSuggestionGenerator).to receive(:new).and_return(generator)
    expect(generator).not_to receive(:call)

    described_class.perform_now(suggestion)
  end

  it 'reclaims a stale analysis' do
    suggestion = create(:ai_agent_learning_suggestion, status: :analyzing, updated_at: 20.minutes.ago)
    stale_updated_at = suggestion.updated_at
    generator = instance_double(AiAgents::LearningSuggestionGenerator)
    allow(AiAgents::LearningSuggestionGenerator).to receive(:new).and_return(generator)
    allow(generator).to receive(:call).and_return(
      AiAgents::LearningSuggestionGenerator::Result.new(useful: false, reason: 'Not reusable')
    )
    described_class.perform_now(suggestion)

    expect(generator).to have_received(:call).once
    expect(suggestion.reload).to be_not_recommended
    expect(suggestion.updated_at).to be > stale_updated_at
  end

  it 'does not persist an old analysis after another worker reclaims it' do
    suggestion = create(:ai_agent_learning_suggestion)
    generator = instance_double(AiAgents::LearningSuggestionGenerator)
    replacement_claim = nil
    allow(AiAgents::LearningSuggestionGenerator).to receive(:new).and_return(generator)
    allow(generator).to receive(:call) do
      suggestion.update!(updated_at: 20.minutes.ago)
      replacement_claim = described_class.new.send(:claim, suggestion)
      AiAgents::LearningSuggestionGenerator::Result.new(useful: false, reason: 'Old result')
    end

    described_class.perform_now(suggestion)

    expect(suggestion.reload).to have_attributes(
      status: 'analyzing',
      claim_id: replacement_claim,
      reason: nil
    )
  end
end
