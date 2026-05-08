require 'rails_helper'

RSpec.describe AiAgentToolExecution do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:ai_agent) }
    it { is_expected.to belong_to(:conversation).optional(true) }
    it { is_expected.to belong_to(:message).optional(true) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:tool_key) }
    it { is_expected.to validate_presence_of(:mode) }
    it { is_expected.to validate_presence_of(:status) }

    it 'requires the AI agent to belong to the same account' do
      execution = build(:ai_agent_tool_execution, ai_agent: create(:ai_agent))

      expect(execution).not_to be_valid
      expect(execution.errors[:ai_agent]).to include('must belong to account')
    end
  end

  describe 'enums' do
    it 'defines execution statuses' do
      expect(described_class.statuses).to eq('executed' => 0, 'error' => 1, 'rejected' => 2)
    end

    it 'defines execution modes' do
      expect(described_class.modes).to eq('test' => 0, 'live' => 1)
    end
  end

  describe 'json defaults' do
    it 'defaults arguments and result to empty hashes' do
      execution = create(:ai_agent_tool_execution, arguments: {}, result: {})

      expect(execution.reload.arguments).to eq({})
      expect(execution.result).to eq({})
    end
  end

  describe 'factory' do
    it 'builds a valid record' do
      expect(build(:ai_agent_tool_execution)).to be_valid
    end
  end
end
