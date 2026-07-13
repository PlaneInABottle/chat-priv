require 'rails_helper'

RSpec.describe AiKnowledgeSourceAssignment do
  it 'rejects a source and assistant from different accounts' do
    source = create(:ai_knowledge_source)
    assistant = create(:ai_agent)
    assignment = described_class.new(
      account: source.account,
      ai_knowledge_source: source,
      assistant: assistant
    )

    expect(assignment).not_to be_valid
    expect(assignment.errors[:account]).to include('must own the source and assistant')
  end
end
