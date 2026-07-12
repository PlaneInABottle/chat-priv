require 'rails_helper'

RSpec.describe VoiceAgents::RuntimeContext do
  describe '#payload' do
    let(:account) { create(:account) }
    let(:api_channel) { create(:channel_api, account: account) }
    let(:inbox) { api_channel.inbox }
    let(:voice_agent) do
      create(
        :voice_agent,
        account: account,
        name: 'Phone voice',
        enabled: true,
        prompt: 'Answer briefly.',
        tools_config: VoiceAgents::Config.new('enabled' => %w[human_handoff end_customer_call]).normalized_config
      )
    end

    it 'returns account-scoped voice agent instructions, tools, and runtime settings' do
      setting = create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      call = create(
        :call,
        account: account,
        inbox: inbox,
        provider: :livekit,
        provider_call_id: 'room-1',
        meta: { 'voice_inbox_setting_id' => setting.id }
      )

      payload = described_class.new(call: call).payload

      expect(payload.dig(:voice_agent, :id)).to eq(voice_agent.id)
      expect(payload[:instructions]).to include('Answer briefly.')
      expect(payload[:tools].pluck(:name)).to include('request_human_handoff', 'end_customer_call')
      expect(payload[:runtime]).to include(
        architecture: voice_agent.architecture,
        provider: voice_agent.provider,
        voice: voice_agent.voice,
        language: voice_agent.language
      )
    end

    it 'ignores a voice_inbox_setting_id from another account' do
      foreign_setting = create(:voice_inbox_setting)
      local_setting = create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      call = create(
        :call,
        account: account,
        inbox: inbox,
        provider: :livekit,
        provider_call_id: 'room-2',
        meta: { 'voice_inbox_setting_id' => foreign_setting.id }
      )

      payload = described_class.new(call: call).payload

      expect(payload.dig(:voice_agent, :id)).to eq(local_setting.voice_agent_id)
    end

    it 'raises when the call has no assigned or explicit voice agent' do
      call = create(
        :call,
        account: account,
        inbox: inbox,
        provider: :livekit,
        provider_call_id: 'room-3',
        meta: {}
      )

      expect { described_class.new(call: call).payload }.to raise_error(ActiveRecord::RecordNotFound, 'Voice agent not configured')
    end

    it 'pins production calls to the published release while sandbox calls use the draft' do
      setting = create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      release = create(:voice_agent_release, voice_agent: voice_agent)
      voice_agent.update!(current_release: release, prompt: 'Unpublished voice draft')
      production_call = create(
        :call,
        account: account,
        inbox: inbox,
        provider: :livekit,
        provider_call_id: 'room-release',
        meta: { 'voice_inbox_setting_id' => setting.id }
      )
      test_call = create(
        :call,
        account: account,
        inbox: inbox,
        conversation: nil,
        contact: nil,
        provider: :livekit,
        provider_call_id: 'room-draft',
        started_at: Time.zone.parse('2026-07-11 12:00:00 UTC'),
        meta: {
          'voice_inbox_setting_id' => setting.id,
          'test_call' => true,
          'ai_improvement_max_duration_seconds' => 20
        }
      )

      production_payload = described_class.new(call: production_call).payload
      test_payload = described_class.new(call: test_call).payload

      expect(production_payload[:instructions]).to include(release.value(:prompt))
      expect(production_payload[:instructions]).not_to include('Unpublished voice draft')
      expect(production_call.reload.voice_agent_release).to eq(release)
      expect(test_payload[:instructions]).to include('Unpublished voice draft')
      expect(test_payload.dig(:call, :voice_agent_release_id)).to be_nil
      expect(test_payload.dig(:call, :test_duration_limit_seconds)).to eq(20)
    end

    it 'adds knowledge search automatically when the runtime snapshot has sources' do
      setting = create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      source = create(:ai_knowledge_source, account: account, name: 'Returns')
      AiKnowledgeSourceAssignment.create!(assistant: voice_agent, ai_knowledge_source: source)
      call = create(
        :call,
        account: account,
        inbox: inbox,
        conversation: nil,
        contact: nil,
        provider: :livekit,
        provider_call_id: 'room-knowledge',
        meta: { 'voice_inbox_setting_id' => setting.id, 'test_call' => true }
      )

      payload = described_class.new(call: call).payload

      expect(payload[:tools].pluck(:name)).to include('search_knowledge')
      expect(payload[:instructions]).to include('Shared knowledge rules:')
    end

    it 'uses the agent that owns a pinned release after the inbox is reassigned' do
      original_agent = voice_agent
      original_release = create(:voice_agent_release, voice_agent: original_agent)
      replacement_agent = create(:voice_agent, account: account, enabled: true, name: 'Replacement voice')
      setting = create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: replacement_agent)
      call = create(
        :call,
        account: account,
        inbox: inbox,
        provider: :livekit,
        provider_call_id: 'room-pinned-agent',
        voice_agent_release: original_release,
        meta: { 'voice_inbox_setting_id' => setting.id }
      )

      payload = described_class.new(call: call).payload

      expect(payload.dig(:voice_agent, :id)).to eq(original_agent.id)
      expect(payload.dig(:voice_agent, :name)).to eq(original_agent.name)
      expect(payload[:instructions]).to include(original_release.value(:prompt))
    end
  end
end
