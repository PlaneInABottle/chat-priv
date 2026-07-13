require 'rails_helper'

RSpec.describe VoiceAgents::Serializer do
  describe '#payload' do
    it 'hides unavailable ikas tools from account-facing payloads' do
      account = create(:account)
      voice_agent = create(
        :voice_agent,
        account: account,
        tools_config: VoiceAgents::Config.new('enabled' => %w[human_handoff ikas_catalog_search]).normalized_config
      )

      payload = described_class.new(voice_agent).payload

      expect(payload).to include(
        id: voice_agent.id,
        account_id: account.id,
        name: voice_agent.name,
        enabled: voice_agent.enabled
      )
      expect(payload[:enabled_tool_keys]).to eq(%w[human_handoff end_customer_call])
      expect(payload.dig(:tools_config, 'enabled')).to eq(%w[human_handoff end_customer_call])
      expect(payload[:available_tools].pluck(:key)).to contain_exactly('human_handoff', 'end_customer_call')
      expect(payload[:ikas_integration]).to include(
        feature_enabled: account.feature_enabled?('ikas_integration')
      )
    end

    it 'includes ikas catalog search when ikas is connected and catalog is synced' do
      account = create(:account)
      account.enable_features('ikas_integration')
      stub_ikas_status(state: 'connected', hook: ikas_hook_with_catalog)
      voice_agent = create(:voice_agent, account: account)

      payload = described_class.new(voice_agent).payload

      expect(payload[:available_tools].pluck(:key)).to include('ikas_lookup_order', 'ikas_catalog_search')
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
    snapshot = instance_double(
      IkasCatalogSnapshot,
      status: 'completed',
      completed_at: Time.current,
      counts: { 'products' => 1, 'catalog_items' => 1 },
      error_message: nil,
      failed?: false,
      sqlite_exists?: true
    )
    snapshots = double
    allow(snapshots).to receive(:order).and_return(double(first: snapshot))
    allow(snapshots).to receive_message_chain(:storefront_catalog, :latest_completed, :first).and_return(snapshot)

    instance_double(Integrations::Hook, ikas_catalog_snapshots: snapshots)
  end
end
