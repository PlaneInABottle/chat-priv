require 'rails_helper'

RSpec.describe AiAgent do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:agent_bot).optional(true) }
  end

  describe 'validations' do
    it { is_expected.to validate_length_of(:prompt).is_at_most(50_000) }

    context 'when account_id uniqueness' do
      let(:account) { create(:account) }

      it 'allows only one AiAgent per account' do
        create(:ai_agent, account: account)

        duplicate = build(:ai_agent, account: account)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:account_id]).to include('has already been taken')
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

      it 'sets the AgentBot name to AI Asistan' do
        ai_agent = create(:ai_agent, account: account)

        expect(ai_agent.agent_bot.name).to eq('AI Asistan')
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
  end
end
