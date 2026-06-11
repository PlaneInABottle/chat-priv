require 'rails_helper'

RSpec.describe VoiceAgents::Serializer do
  describe '#payload' do
    it 'includes normalized tools and ikas connection summary' do
      account = create(:account)
      voice_agent = account.voice_agents.first
      voice_agent.update!(
        tools_config: VoiceAgents::Config.new('enabled' => %w[human_handoff ikas_catalog_search]).normalized_config
      )

      payload = described_class.new(voice_agent).payload

      expect(payload).to include(
        id: voice_agent.id,
        account_id: account.id,
        name: voice_agent.name,
        enabled: voice_agent.enabled
      )
      expect(payload[:enabled_tool_keys]).to eq(%w[human_handoff ikas_catalog_search])
      expect(payload.dig(:tools_config, 'enabled')).to eq(%w[human_handoff ikas_catalog_search])
      expect(payload[:available_tools].pluck(:key)).to include('human_handoff', 'ikas_catalog_search', 'end_customer_call')
      expect(payload[:ikas_integration]).to include(
        feature_enabled: account.feature_enabled?('ikas_integration')
      )
    end
  end
end
