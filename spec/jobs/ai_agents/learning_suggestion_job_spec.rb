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
      destination: 'knowledge',
      source_name: 'Returns policy',
      target_section: nil,
      suggested_instruction: 'Returns are accepted within 14 days.'
    )
  end
end
