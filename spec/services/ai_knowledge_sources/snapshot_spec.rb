require 'rails_helper'

RSpec.describe AiKnowledgeSources::Snapshot do
  it 'captures selected source content in a stable order' do
    assistant = create(:ai_agent)
    later_source = create(:ai_knowledge_source, account: assistant.account, name: 'Later')
    earlier_source = create(:ai_knowledge_source, account: assistant.account, name: 'Earlier')
    AiKnowledgeSources::AssignmentSync.new(
      assistant: assistant,
      source_ids: [later_source.id, earlier_source.id]
    ).perform

    snapshot = described_class.for(assistant)

    expect(snapshot.pluck('id')).to eq([later_source.id, earlier_source.id].sort)
    expect(snapshot.first).to include('name', 'content', 'source_type', 'updated_at')
  end

  it 'keeps a captured release stable when the shared source changes' do
    assistant = create(:ai_agent, prompt: 'Answer from verified sources.')
    source = create(:ai_knowledge_source, account: assistant.account, content: 'Original policy')
    AiKnowledgeSources::AssignmentSync.new(assistant: assistant, source_ids: [source.id]).perform
    release_snapshot = AiAgents::ReleaseSnapshot.for(assistant)
    release_fingerprint = AiAgents::ReleaseSnapshot.fingerprint(release_snapshot)

    source.update!(content: 'Updated policy')

    expect(release_snapshot.dig('knowledge_sources', 0, 'content')).to eq('Original policy')
    expect(AiAgents::ReleaseSnapshot.fingerprint(AiAgents::ReleaseSnapshot.for(assistant))).not_to eq(release_fingerprint)
  end

  it 'omits website sources until they have readable synced content' do
    assistant = create(:ai_agent)
    source = create(:ai_knowledge_source, :website, account: assistant.account)
    AiKnowledgeSources::AssignmentSync.new(assistant: assistant, source_ids: [source.id]).perform

    expect(described_class.for(assistant)).to eq([])
  end

  it 'does not mark a newer source revision as tested' do
    assistant = create(:ai_agent, prompt: 'Answer from verified sources.')
    source = create(:ai_knowledge_source, account: assistant.account, content: 'Original policy')
    AiKnowledgeSources::AssignmentSync.new(assistant: assistant, source_ids: [source.id]).perform
    tested_fingerprint = assistant.draft_fingerprint
    source.update!(content: 'Updated policy')

    assistant.mark_test_succeeded!(tested_fingerprint: tested_fingerprint)

    expect(assistant).not_to be_draft_tested
  end
end
