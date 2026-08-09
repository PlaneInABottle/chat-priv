require 'rails_helper'

RSpec.describe AiAgents::Readiness do
  let(:ai_agent) { create(:ai_agent) }
  let(:inbox) { create(:inbox, account: ai_agent.account) }

  before do
    AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: ai_agent.account)
  end

  it 'keeps the test check optional for publication' do
    readiness = described_class.new(ai_agent).payload
    test_check = readiness[:checks].find { |check| check[:key] == 'test' }

    expect(test_check).to include(complete: false, blocking: false)
    expect(readiness[:can_publish]).to be(true)
  end

  it 'marks a successful test of the current draft complete' do
    ai_agent.mark_test_succeeded!

    readiness = described_class.new(ai_agent.reload).payload
    test_check = readiness[:checks].find { |check| check[:key] == 'test' }

    expect(test_check).to include(complete: true, blocking: false)
    expect(readiness[:can_publish]).to be(true)
  end

  it 'invalidates the test check when the prompt, config, or knowledge changes' do
    scenarios = [
      -> { ai_agent.update!(prompt: 'Changed instructions') },
      -> { ai_agent.update!(config: { 'tools' => { 'enabled' => ['human_handoff'] } }) },
      lambda do
        source = create(:ai_knowledge_source, account: ai_agent.account)
        AiKnowledgeSourceAssignment.create!(assistant: ai_agent, ai_knowledge_source: source)
        source.update!(content: 'Changed business information')
      end
    ]

    scenarios.each do |change|
      ai_agent.mark_test_succeeded!
      change.call

      readiness = described_class.new(ai_agent.reload).payload
      test_check = readiness[:checks].find { |check| check[:key] == 'test' }

      expect(test_check).to include(complete: false, blocking: false)
      expect(readiness[:can_publish]).to be(true)
    end
  end
end
