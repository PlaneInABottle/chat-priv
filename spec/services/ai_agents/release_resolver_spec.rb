require 'rails_helper'

RSpec.describe AiAgents::ReleaseResolver do
  it 'pins the current release once for the conversation' do
    ai_agent = create(:ai_agent)
    first_release = create(:ai_agent_release, ai_agent: ai_agent, revision: 1)
    ai_agent.update!(current_release: first_release)
    conversation = create(:conversation, account: ai_agent.account)

    expect(described_class.for(conversation: conversation, ai_agent: ai_agent)).to eq(first_release)

    second_release = create(:ai_agent_release, ai_agent: ai_agent, revision: 2)
    ai_agent.update!(current_release: second_release)

    expect(described_class.for(conversation: conversation.reload, ai_agent: ai_agent)).to eq(first_release)
    expect(conversation.reload.ai_agent_release).to eq(first_release)
  end

  it 'keeps a concurrent pin when resolving from a stale conversation instance' do
    ai_agent = create(:ai_agent)
    first_release = create(:ai_agent_release, ai_agent: ai_agent, revision: 1)
    second_release = create(:ai_agent_release, ai_agent: ai_agent, revision: 2)
    conversation = create(:conversation, account: ai_agent.account)
    stale_conversation = Conversation.find(conversation.id)
    stale_conversation.ai_agent_release

    conversation.update!(ai_agent_release: first_release)
    ai_agent.update!(current_release: second_release)

    resolved = described_class.for(conversation: stale_conversation, ai_agent: ai_agent)

    expect(resolved).to eq(first_release)
    expect(stale_conversation.reload.ai_agent_release).to eq(first_release)
  end
end
