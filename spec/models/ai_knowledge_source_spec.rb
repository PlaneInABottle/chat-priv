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

  it 'normalizes website URLs and allows content to remain empty while pending' do
    source = build(:ai_knowledge_source, :website, website_url: 'example.com/returns')

    expect(source).to be_valid
    expect(source).to have_attributes(
      website_url: 'https://example.com/returns',
      sync_status: 'pending',
      content: ''
    )
  end

  it 'rejects invalid website URLs' do
    source = build(:ai_knowledge_source, :website, website_url: 'javascript:alert(1)')

    expect(source).not_to be_valid
    expect(source.errors[:website_url]).to be_present
  end
end
