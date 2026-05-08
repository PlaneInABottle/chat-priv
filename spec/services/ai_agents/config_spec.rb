require 'rails_helper'

RSpec.describe AiAgents::Config do
  describe '#valid?' do
    it 'defaults human handoff on when config is nil' do
      config = described_class.new(nil)

      expect(config.enabled_tool_keys).to eq(['human_handoff'])
    end

    it 'defaults human handoff on when config is not an object' do
      config = described_class.new('bad')

      expect(config.enabled_tool_keys).to eq(['human_handoff'])
    end

    it 'defaults human handoff on when tools config is missing' do
      config = described_class.new({ 'other' => true })

      expect(config.tools_summary['enabled']).to eq(['human_handoff'])
      expect(config.normalized_config).to eq({ 'other' => true })
    end

    it 'defaults human handoff on when tools enabled is missing' do
      config = described_class.new({ 'tools' => { 'human_handoff' => { 'allowed_labels' => ['vip'] } } })

      expect(config.enabled_tool_keys).to eq(['human_handoff'])
      expect(config.normalized_config['tools']['enabled']).to eq(['human_handoff'])
    end

    it 'respects an explicit empty enabled array as opt-out' do
      config = described_class.new({ 'tools' => { 'enabled' => [] } })

      expect(config.enabled_tool_keys).to eq([])
      expect(config.tools_summary['enabled']).to eq([])
    end

    it 'does not default-enable ikas lookup order' do
      config = described_class.new({})

      expect(config.enabled_tool_keys).not_to include('ikas_lookup_order')
    end

    it 'rejects unknown tool keys inside tools subtree' do
      config = described_class.new({ 'tools' => { 'enabled' => ['unknown_tool'] } })

      expect(config).not_to be_valid
      expect(config.errors).to include('config.tools.enabled contains unknown tools: unknown_tool')
    end

    it 'preserves unknown sibling keys outside tools subtree' do
      config = described_class.new({ 'foo' => { 'bar' => true }, 'tools' => { 'enabled' => ['human_handoff'] } })

      expect(config.normalized_config['foo']).to eq({ 'bar' => true })
      expect(config.enabled_tool_keys).to eq(['human_handoff'])
    end

    it 'rejects removed human handoff config keys' do
      config = described_class.new({
                                     'tools' => {
                                       'human_handoff' => {
                                         'allowed_labels' => ['vip'],
                                         'transfer_message' => 'Please wait.',
                                         'preview_only' => true
                                       }
                                     }
                                   })

      expect(config).not_to be_valid
      expect(config.errors).to include('config.tools.human_handoff contains unknown keys: transfer_message, preview_only')
    end

    it 'allows legacy human handoff config keys only in compatibility mode' do
      config = described_class.new({
                                     'tools' => {
                                       'human_handoff' => {
                                         'allowed_labels' => ['vip'],
                                         'transfer_message' => 'Please wait.',
                                         'preview_only' => true
                                       }
                                     }
                                   }, allow_legacy_human_handoff_settings: true)

      expect(config).to be_valid
      expect(config.tools_summary['human_handoff']).to eq({ 'allowed_labels' => ['vip'] })
    end

    it 'rejects truly unknown human handoff config keys in compatibility mode' do
      config = described_class.new({
                                     'tools' => {
                                       'human_handoff' => {
                                         'allowed_labels' => ['vip'],
                                         'unexpected_key' => true,
                                         'transfer_message' => 'Please wait.'
                                       }
                                     }
                                   }, allow_legacy_human_handoff_settings: true)

      expect(config).not_to be_valid
      expect(config.errors).to include('config.tools.human_handoff contains unknown keys: unexpected_key')
    end

    it 'normalizes allowed labels and strips unknown nested human handoff keys from summary' do
      config = described_class.new({
                                     'foo' => { 'bar' => true },
                                     'tools' => {
                                       'enabled' => ['human_handoff'],
                                       'human_handoff' => {
                                         'allowed_labels' => ['vip', '', 'billing', 'vip']
                                       }
                                     }
                                   })

      expect(config).to be_valid
      expect(config.tools_summary).to include(
        'enabled' => ['human_handoff'],
        'human_handoff' => { 'allowed_labels' => %w[vip billing] }
      )
      expect(config.normalized_config['foo']).to eq({ 'bar' => true })
    end
  end
end
