require 'rails_helper'

RSpec.describe AiAgents::ToolAvailability do
  let(:account) { create(:account) }

  describe '#available_keys' do
    it 'hides ikas tools when ikas is not connected' do
      account.enable_features('ikas_integration')

      keys = described_class.new(account: account).available_keys(AiAgents::ToolRegistry.available_definitions)

      expect(keys).to eq(['human_handoff'])
    end

    it 'shows order lookup when ikas is connected' do
      account.enable_features('ikas_integration')
      stub_ikas_status(state: 'connected')

      keys = described_class.new(account: account).available_keys(AiAgents::ToolRegistry.available_definitions)

      expect(keys).to include('human_handoff', 'ikas_lookup_order')
      expect(keys).not_to include('ikas_catalog_search')
    end

    it 'shows catalog search when ikas has a completed storefront catalog snapshot' do
      account.enable_features('ikas_integration')
      stub_ikas_status(state: 'connected', hook: ikas_hook_with_catalog)

      keys = described_class.new(account: account).available_keys(AiAgents::ToolRegistry.available_definitions)

      expect(keys).to include('human_handoff', 'ikas_lookup_order', 'ikas_catalog_search')
    end
  end

  describe '#filter_tools_config' do
    it 'keeps human handoff when the payload has no enabled tools' do
      filtered = described_class.new(account: account).filter_tools_config({}, AiAgents::ToolRegistry.available_definitions)

      expect(filtered['enabled']).to eq(['human_handoff'])
    end

    it 'strips unavailable ikas tools from a config payload' do
      config = {
        'enabled' => %w[human_handoff ikas_lookup_order ikas_catalog_search],
        'ikas_lookup_order' => { 'enabled' => true }
      }

      filtered = described_class.new(account: account).filter_tools_config(config, AiAgents::ToolRegistry.available_definitions)

      expect(filtered['enabled']).to eq(['human_handoff'])
      expect(filtered.dig('ikas_lookup_order', 'enabled')).to be false
    end
  end

  def stub_ikas_status(state:, hook: nil)
    allow_any_instance_of(Integrations::Ikas::ConnectionStatus).to receive(:payload).and_return(
      state: state,
      hook: hook,
      can_connect: true
    )
  end

  def ikas_hook_with_catalog
    snapshot = instance_double(IkasCatalogSnapshot, sqlite_exists?: true)
    snapshots = double
    allow(snapshots).to receive_message_chain(:storefront_catalog, :latest_completed, :first).and_return(snapshot)

    instance_double(Integrations::Hook, ikas_catalog_snapshots: snapshots)
  end
end
