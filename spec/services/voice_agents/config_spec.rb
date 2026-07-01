require 'rails_helper'

RSpec.describe VoiceAgents::Config do
  describe '#normalized_config' do
    it 'defaults to human handoff and ending customer calls' do
      config = described_class.new({})

      expect(config.normalized_config['enabled']).to eq(%w[human_handoff end_customer_call])
      expect(config.tool_settings('human_handoff')).to eq('allowed_labels' => [])
    end

    it 'normalizes known tool keys and drops unknown enabled tools' do
      config = described_class.new(
        'enabled' => ['human_handoff', 'unknown', 'ikas_catalog_search'],
        'human_handoff' => { 'allowed_labels' => ['vip', '', 'vip'] }
      )

      expect(config.enabled_tool_keys).to eq(%w[human_handoff ikas_catalog_search])
      expect(config.tool_settings('human_handoff')).to eq('allowed_labels' => ['vip'])
    end
  end

  describe '#errors' do
    it 'validates enabled and per-tool settings shape' do
      config = described_class.new(
        'enabled' => 'human_handoff',
        'unknown_tool' => {},
        'human_handoff' => 'invalid'
      )

      expect(config).not_to be_valid
      expect(config.errors).to include(
        'tools_config.enabled must be an array',
        'tools_config contains unknown keys: unknown_tool',
        'tools_config.human_handoff must be an object'
      )
    end
  end
end
