require 'rails_helper'

RSpec.describe AiKnowledgeSources::AssignmentSync do
  it 'replaces an assistant selection with account-owned sources' do
    assistant = create(:ai_agent)
    first_source = create(:ai_knowledge_source, account: assistant.account)
    second_source = create(:ai_knowledge_source, account: assistant.account)
    described_class.new(assistant: assistant, source_ids: [first_source.id]).perform

    described_class.new(assistant: assistant, source_ids: [second_source.id]).perform

    expect(assistant.reload.knowledge_sources).to contain_exactly(second_source)
    expect(assistant.knowledge_source_assignments.first.account).to eq(assistant.account)
  end

  it 'rejects sources outside the assistant account' do
    assistant = create(:voice_agent)
    foreign_source = create(:ai_knowledge_source)

    expect do
      described_class.new(assistant: assistant, source_ids: [foreign_source.id]).perform
    end.to raise_error(ActiveRecord::RecordNotFound)
  end

  it 'limits release snapshot growth per assistant' do
    assistant = create(:ai_agent)
    source_ids = (1..(described_class::MAX_SOURCES + 1)).to_a

    expect do
      described_class.new(assistant: assistant, source_ids: source_ids).perform
    end.to raise_error(ActiveRecord::RecordInvalid, /can include up to 20 sources/)
  end
end
