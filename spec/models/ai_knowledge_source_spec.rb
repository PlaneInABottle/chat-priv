require 'rails_helper'

RSpec.describe AiKnowledgeSource do
  it 'normalizes manual source text' do
    source = build(:ai_knowledge_source, name: '  Returns  ', content: "  Returns are accepted.\n")

    source.validate

    expect(source).to have_attributes(name: 'Returns', content: 'Returns are accepted.')
  end

  it 'limits source content size' do
    source = build(:ai_knowledge_source, content: 'a' * (described_class::MAX_CONTENT_LENGTH + 1))

    expect(source).not_to be_valid
    expect(source.errors[:content]).to be_present
  end
end
