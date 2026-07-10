require 'rails_helper'

RSpec.describe AiAgent do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:agent_bot).optional(true) }
    it { is_expected.to have_many(:llm_calls).class_name('AiAgentLlmCall').dependent(:destroy) }
    it { is_expected.to have_many(:tool_executions).class_name('AiAgentToolExecution').dependent(:destroy) }
    it { is_expected.to have_many(:evaluation_cases).class_name('AiAgentEvaluationCase').dependent(:destroy) }
    it { is_expected.to have_many(:evaluation_runs).class_name('AiAgentEvaluationRun').dependent(:destroy) }
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

  describe 'lifecycle' do
    let(:account) { create(:account) }
    let(:ai_agent) { create(:ai_agent, account: account) }

    it 'moves a tested draft through active and paused states' do
      inbox = create(:inbox, account: account)
      AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: account)
      ai_agent.mark_test_succeeded!

      expect(ai_agent.reload.lifecycle_status).to eq('draft')
      expect(ai_agent.readiness[:can_publish]).to be(true)

      ai_agent.publish!
      expect(ai_agent).to have_attributes(
        enabled: true,
        published_prompt: ai_agent.prompt,
        published_config: ai_agent.config,
        published_revision: 1
      )
      expect(ai_agent.lifecycle_status).to eq('active')
      expect(ai_agent.published_at).to be_present
      tested_at = ai_agent.last_tested_at

      ai_agent.pause!
      expect(ai_agent).to have_attributes(enabled: false, last_tested_at: tested_at)
      expect(ai_agent.lifecycle_status).to eq('paused')
    end

    it 'requires the current prompt to match the successfully tested prompt' do
      ai_agent.mark_test_succeeded!

      expect(ai_agent.reload.prompt_tested?).to be(true)

      ai_agent.update!(prompt: 'Changed after the test')

      expect(ai_agent.prompt_tested?).to be(false)
    end

    it 'keeps the published release live while a tested update is prepared', :aggregate_failures do
      inbox = create(:inbox, account: account)
      AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: account)
      ai_agent.mark_test_succeeded!
      ai_agent.publish!

      published_prompt = ai_agent.live_prompt
      ai_agent.update!(prompt: 'A new draft', config: { 'tools' => { 'enabled' => %w[human_handoff ikas_catalog_search] } })

      expect(ai_agent).to have_attributes(enabled: true, published_revision: 1)
      expect(ai_agent.live_prompt).to eq(published_prompt)
      expect(ai_agent.live_config).to eq({})
      expect(ai_agent.draft_changes?).to be(true)
      expect(ai_agent.draft_tested?).to be(false)

      ai_agent.mark_test_succeeded!
      ai_agent.publish!

      expect(ai_agent).to have_attributes(published_prompt: 'A new draft', published_revision: 2)
      expect(ai_agent.live_config.dig('tools', 'enabled')).to contain_exactly('human_handoff', 'ikas_catalog_search')
      expect(ai_agent.draft_changes?).to be(false)
    end

    it 'resumes an unchanged published release without incrementing its revision' do
      inbox = create(:inbox, account: account)
      AgentBotInbox.create!(agent_bot: ai_agent.agent_bot, inbox: inbox, account: account)
      ai_agent.mark_test_succeeded!
      ai_agent.publish!
      ai_agent.pause!

      expect { ai_agent.publish! }.not_to change(ai_agent, :published_revision)
      expect(ai_agent).to be_enabled
    end

    it 'requires another test when draft capabilities change' do
      ai_agent.mark_test_succeeded!
      expect(ai_agent).to be_draft_tested

      ai_agent.update!(config: { 'tools' => { 'enabled' => %w[human_handoff ikas_catalog_search] } })

      expect(ai_agent).not_to be_draft_tested
    end
  end
end
