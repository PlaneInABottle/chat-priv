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
  end
end
