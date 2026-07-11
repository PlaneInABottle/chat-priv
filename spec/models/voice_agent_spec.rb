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

    it 'accepts the supported OpenAI realtime runtime' do
      voice_agent = build(
        :voice_agent,
        architecture: 'realtime',
        provider: 'openai',
        model: 'gpt-realtime-2.1',
        voice: 'marin'
      )

      expect(voice_agent).to be_valid
    end

    it 'rejects incompatible OpenAI realtime model and voice values' do
      voice_agent = build(
        :voice_agent,
        architecture: 'realtime',
        provider: 'openai',
        model: 'gemini-3.1-flash-live-preview',
        voice: 'Charon'
      )

      expect(voice_agent).not_to be_valid
      expect(voice_agent.errors[:model]).to include('must be a supported OpenAI realtime model')
      expect(voice_agent.errors[:voice]).to include('must be a supported OpenAI realtime voice')
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

    it 'keeps the live release stable while editing and supports rollback' do
      inbox = create(:channel_api, account: account).inbox
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      voice_agent.mark_test_succeeded!
      voice_agent.publish!
      first_release = voice_agent.current_release

      voice_agent.update!(prompt: 'A new voice draft')

      expect(voice_agent).to be_draft_changes
      expect(voice_agent.live_value(:prompt)).to eq(first_release.value(:prompt))
      expect(voice_agent).not_to be_draft_tested

      voice_agent.mark_test_succeeded!
      voice_agent.publish!
      restored = voice_agent.rollback_to!(first_release)

      expect(voice_agent.reload).to have_attributes(prompt: first_release.value(:prompt), current_release: restored)
      expect(restored).to have_attributes(source: 'rollback', revision: 3)
    end
  end
end
