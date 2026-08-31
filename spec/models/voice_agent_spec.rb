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

  describe 'authoring profile' do
    it 'normalizes reads, validates partial writes, and preserves sibling config' do
      voice_agent = build(
        :voice_agent,
        config: {
          'runtime_key' => 'keep',
          'authoring_profile' => { 'tone' => 'invalid', 'business_context' => 'Valid', 'boundaries' => 3 }
        }
      )

      expect(voice_agent.authoring_profile).to eq(
        'tone' => 'friendly', 'business_context' => 'Valid', 'boundaries' => ''
      )

      voice_agent.merge_authoring_profile('tone' => 'concise')
      expect(voice_agent.config).to include('runtime_key' => 'keep')
      expect(voice_agent.authoring_profile).to eq(
        'tone' => 'concise', 'business_context' => 'Valid', 'boundaries' => ''
      )
      expect(voice_agent.runtime_config).to eq('runtime_key' => 'keep')

      expect { voice_agent.merge_authoring_profile('boundaries' => nil) }.to raise_error(ActiveRecord::RecordInvalid)
      expect(voice_agent.errors[:authoring_profile]).to include(/boundaries must be a string/)
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
      voice_agent.pause!
      restored = voice_agent.rollback_to!(first_release)

      expect(voice_agent.reload).to have_attributes(prompt: first_release.value(:prompt), current_release: restored, enabled: false)
      expect(restored).to have_attributes(source: 'rollback', revision: 3)
    end

    it 'keeps authoring-only changes out of release identity and test readiness' do
      inbox = create(:channel_api, account: account).inbox
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      voice_agent.mark_test_succeeded!
      fingerprint = voice_agent.draft_fingerprint
      tested_at = voice_agent.last_tested_at
      readiness = voice_agent.readiness

      voice_agent.merge_authoring_profile('tone' => 'concise', 'business_context' => 'Store context')
      voice_agent.save!

      expect(voice_agent).to have_attributes(
        draft_fingerprint: fingerprint,
        last_tested_at: tested_at,
        last_tested_draft_fingerprint: fingerprint
      )
      expect(voice_agent).to be_draft_tested
      expect(voice_agent.readiness).to eq(readiness)

      voice_agent.publish!
      release = voice_agent.current_release
      voice_agent.merge_authoring_profile('boundaries' => 'Do not approve refunds')
      voice_agent.save!
      voice_agent.publish!

      expect(voice_agent.current_release).to eq(release)
      expect(voice_agent.published_revision).to eq(1)
      expect(release.snapshot.fetch('config')).not_to have_key('authoring_profile')
    end

    it 'sanitizes contaminated historical releases and preserves the current profile during rollback' do
      historical_source = create(:ai_knowledge_source, account: account, name: 'Historical')
      current_source = create(:ai_knowledge_source, account: account, name: 'Current')
      voice_agent.knowledge_sources = [current_source]
      voice_agent.update!(
        prompt: 'Current prompt',
        config: {
          'runtime_key' => 'current',
          'authoring_profile' => { 'tone' => 'professional', 'business_context' => 'Canonical', 'boundaries' => '' }
        }
      )
      contaminated_snapshot = VoiceAgents::ReleaseSnapshot.for(voice_agent).merge(
        'prompt' => 'Historical prompt',
        'config' => {
          'runtime_key' => 'historical',
          'authoring_profile' => { 'tone' => 'concise', 'business_context' => 'Stale' }
        },
        'knowledge_sources' => [{ 'id' => historical_source.id }]
      )
      source_copy = contaminated_snapshot.deep_dup
      historical_release = create(
        :voice_agent_release,
        voice_agent: voice_agent,
        account: account,
        snapshot: contaminated_snapshot,
        fingerprint: AssistantReleases::Snapshot.fingerprint(contaminated_snapshot)
      )

      restored = voice_agent.rollback_to!(historical_release)
      voice_agent.reload

      expect(contaminated_snapshot).to eq(source_copy)
      expect(restored.snapshot).to eq(VoiceAgents::ReleaseSnapshot.sanitize(source_copy))
      expect(restored.fingerprint).to eq(AssistantReleases::Snapshot.fingerprint(restored.snapshot))
      expect(voice_agent).to have_attributes(prompt: 'Historical prompt', current_release: restored)
      expect(voice_agent.runtime_config).to eq('runtime_key' => 'historical')
      expect(voice_agent.authoring_profile).to eq(
        'tone' => 'professional', 'business_context' => 'Canonical', 'boundaries' => ''
      )
      expect(voice_agent.knowledge_source_ids).to contain_exactly(historical_source.id)
    end

    it 'can publish paused and activate the tested release independently of later draft edits' do
      inbox = create(:channel_api, account: account).inbox
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      voice_agent.mark_test_succeeded!

      voice_agent.publish!(activate: false)
      published_prompt = voice_agent.current_release.value(:prompt)

      expect(voice_agent).to have_attributes(enabled: false, lifecycle_status: 'paused')

      voice_agent.update!(prompt: 'Untested next draft')
      voice_agent.activate!

      expect(voice_agent).to be_enabled
      expect(voice_agent.live_value(:prompt)).to eq(published_prompt)
    end

    it 'does not activate an unpublished assistant' do
      expect { voice_agent.activate! }.to raise_error(ActiveRecord::RecordInvalid, /Publish the assistant before activation/)
      expect(voice_agent).not_to be_enabled
    end

    it 'rechecks readiness after acquiring the publish lock' do
      inbox = create(:channel_api, account: account).inbox
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      voice_agent.mark_test_succeeded!
      allow(voice_agent).to receive(:with_lock).and_wrap_original do |original, *args, &block|
        voice_agent.update!(prompt: 'Changed after the initial request check')
        original.call(*args, &block)
      end

      expect { voice_agent.publish! }.to raise_error(ActiveRecord::RecordInvalid)
      expect(voice_agent.reload.current_release).to be_nil
    end
  end
end
