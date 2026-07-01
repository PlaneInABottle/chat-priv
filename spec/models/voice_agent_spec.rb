require 'rails_helper'

RSpec.describe VoiceAgent do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:voice_inbox_settings).dependent(:nullify) }
  end

  describe 'validations' do
    it 'rejects invalid tools config' do
      voice_agent = build(:voice_agent, tools_config: { 'enabled' => 'human_handoff' })

      expect(voice_agent).not_to be_valid
      expect(voice_agent.errors[:tools_config]).to include('tools_config.enabled must be an array')
    end
  end
end
