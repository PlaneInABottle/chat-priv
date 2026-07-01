require 'rails_helper'

RSpec.describe AiAgent do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:agent_bot).optional(true) }
    it { is_expected.to have_many(:llm_calls).class_name('AiAgentLlmCall').dependent(:destroy) }
    it { is_expected.to have_many(:tool_executions).class_name('AiAgentToolExecution').dependent(:destroy) }
    it { is_expected.to have_many(:usage_events).class_name('AiAgentUsageEvent').dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:prompt).is_at_most(50_000) }

    context 'when multiple agents per account' do
      let(:account) { create(:account) }

      it 'allows multiple AiAgents per account' do
        create(:ai_agent, account: account, name: 'First Agent')

        second = build(:ai_agent, account: account, name: 'Second Agent')
        expect(second).to be_valid
      end
    end

    context 'when assigning an inbox already bound to another AI agent' do
      let(:account) { create(:account) }
      let(:inbox) { create(:inbox, account: account) }

      it 'is invalid when inbox is already assigned to another AI agent' do
        first_agent = create(:ai_agent, account: account, name: 'First Agent')
        AgentBotInbox.create!(agent_bot: first_agent.agent_bot, inbox: inbox, account: account)

        second_agent = build(:ai_agent, account: account, name: 'Second Agent', inbox_ids: [inbox.id])
        expect(second_agent).not_to be_valid
        expect(second_agent.errors[:inbox_ids]).to include('already assigned to another agent bot')
      end

      it 'is valid when inbox is assigned to the same agent' do
        agent = create(:ai_agent, account: account, name: 'My Agent')
        AgentBotInbox.create!(agent_bot: agent.agent_bot, inbox: inbox, account: account)

        agent.inbox_ids = [inbox.id]
        expect(agent).to be_valid
      end

      it 'is invalid when inbox is already assigned to a webhook bot' do
        webhook_bot = create(:agent_bot, account: account)
        AgentBotInbox.create!(agent_bot: webhook_bot, inbox: inbox, account: account)

        ai_agent = build(:ai_agent, account: account, name: 'Second Agent', inbox_ids: [inbox.id])
        expect(ai_agent).not_to be_valid
        expect(ai_agent.errors[:inbox_ids]).to include('already assigned to another agent bot')
      end
    end

    context 'when validating tools config' do
      let(:account) { create(:account) }

      it 'rejects unknown tools in config.tools.enabled' do
        ai_agent = build(:ai_agent, account: account, config: { 'tools' => { 'enabled' => ['unknown_tool'] } })

        expect(ai_agent).not_to be_valid
        expect(ai_agent.errors[:config]).to include('config.tools.enabled contains unknown tools: unknown_tool')
      end

      it 'allows known tools and preserves sibling config keys' do
        ai_agent = build(:ai_agent, account: account, config: {
          'other' => { 'persist' => true },
          'tools' => { 'enabled' => ['human_handoff'] }
        })

        expect(ai_agent).to be_valid
        expect(ai_agent.config['other']).to eq({ 'persist' => true })
      end
    end
  end

  describe 'callbacks' do
    let(:account) { create(:account) }

    context 'when after_create' do
      it 'creates a linked AgentBot with bot_type ai' do
        ai_agent = create(:ai_agent, account: account)

        expect(ai_agent.agent_bot).not_to be_nil
        expect(ai_agent.agent_bot.bot_type).to eq('ai')
      end

      it 'sets the AgentBot name to the AiAgent name' do
        ai_agent = create(:ai_agent, account: account, name: 'Custom Agent')

        expect(ai_agent.agent_bot.name).to eq('Custom Agent')
      end

      it 'sets the AgentBot outgoing_url to nil' do
        ai_agent = create(:ai_agent, account: account)

        expect(ai_agent.agent_bot.outgoing_url).to be_nil
      end

      it 'associates the AgentBot with the same account' do
        ai_agent = create(:ai_agent, account: account)

        expect(ai_agent.agent_bot.account_id).to eq(account.id)
      end
    end

    context 'when before_destroy' do
      it 'removes linked inbox bindings before destroying the agent bot' do
        ai_agent = create(:ai_agent, account: account)
        inbox = create(:inbox, account: account)
        AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: account)

        ai_agent.destroy!

        expect(AgentBotInbox.where(agent_bot_id: ai_agent.agent_bot_id, inbox_id: inbox.id)).to be_empty
      end
    end
  end

  describe 'defaults' do
    it 'has prompt defaulting to empty string' do
      ai_agent = described_class.new
      expect(ai_agent.prompt).to eq('')
    end

    it 'has enabled defaulting to false' do
      ai_agent = described_class.new
      expect(ai_agent.enabled).to be(false)
    end

    it 'has config defaulting to empty hash' do
      ai_agent = described_class.new
      expect(ai_agent.config).to eq({})
    end

    it 'has name defaulting to AI Asistan' do
      ai_agent = described_class.new
      expect(ai_agent.name).to eq('AI Asistan')
    end
  end

  describe 'factory' do
    it 'builds a valid record' do
      expect(build(:ai_agent)).to be_valid
    end
  end
end
