require 'rails_helper'

RSpec.describe AiKnowledgeSources::ReleaseAssignmentRestore do
  it 'restores only sources that still exist in the account library' do
    assistant = create(:voice_agent)
    retained_source = create(:ai_knowledge_source, account: assistant.account)
    deleted_source = create(:ai_knowledge_source, account: assistant.account)
    snapshot = {
      'knowledge_sources' => [retained_source, deleted_source].map { |source| { 'id' => source.id } }
    }
    deleted_source.destroy!

    described_class.new(assistant: assistant, snapshot: snapshot).perform

    expect(assistant.reload.knowledge_sources).to contain_exactly(retained_source)
  end
end
