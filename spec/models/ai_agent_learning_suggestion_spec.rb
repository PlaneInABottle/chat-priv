require 'rails_helper'

RSpec.describe AiAgentLearningSuggestion do
  it 'requires a source name for reviewed knowledge' do
    suggestion = create(
      :ai_agent_learning_suggestion,
      :knowledge_ready
    )
    suggestion.source_name = nil

    expect(suggestion).not_to be_valid
    expect(suggestion.errors[:source_name]).to be_present
  end

  it 'does not require an instruction section for reviewed knowledge' do
    suggestion = create(:ai_agent_learning_suggestion, :knowledge_ready)

    expect(suggestion).to be_valid
    expect(suggestion.target_section).to be_nil
  end
end
