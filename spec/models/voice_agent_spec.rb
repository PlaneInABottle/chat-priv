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

  describe 'lifecycle' do
    let(:account) { create(:account) }
    let(:voice_agent) { create(:voice_agent, account: account, enabled: false) }

    it 'requires greeting, instructions, inbox, and a successful test before publishing' do
      inbox = create(:channel_api, account: account).inbox
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)

      expect(voice_agent.readiness[:can_publish]).to be(false)
      voice_agent.mark_test_succeeded!
      expect(voice_agent.reload.readiness[:can_publish]).to be(true)

      voice_agent.publish!
      expect(voice_agent.lifecycle_status).to eq('active')

      tested_at = voice_agent.last_tested_at
      voice_agent.pause!
      expect(voice_agent).to have_attributes(enabled: false, last_tested_at: tested_at)
      expect(voice_agent.lifecycle_status).to eq('paused')
    end
  end
end
