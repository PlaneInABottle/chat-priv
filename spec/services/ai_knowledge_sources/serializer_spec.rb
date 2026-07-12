require 'rails_helper'

RSpec.describe AiKnowledgeSources::Serializer do
  it 'keeps full content out of collection payloads' do
    source = create(:ai_knowledge_source, content: 'a' * 200)

    payload = described_class.new(source).payload

    expect(payload).not_to have_key(:content)
    expect(payload[:content_preview]).to eq("#{'a' * 160}...")
    expect(payload[:character_count]).to eq(200)
  end

  it 'includes full content for an individual source' do
    source = create(:ai_knowledge_source, content: 'Verified policy')

    payload = described_class.new(source, include_content: true).payload

    expect(payload).to include(content: 'Verified policy', content_preview: 'Verified policy')
  end
end
