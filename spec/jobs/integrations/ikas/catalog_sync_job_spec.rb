require 'rails_helper'

RSpec.describe Integrations::Ikas::CatalogSyncJob do
  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, :ikas, account: account) }

  before do
    Integrations::Hook.name
    allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    account.enable_features('ikas_integration')
    account.save!
  end

  it 'creates a snapshot for the connected hook and runs the sync runner' do
    runner = instance_double(Integrations::Ikas::Catalog::SyncRunner)
    allow(Integrations::Ikas::Catalog::SyncRunner).to receive(:new).and_return(runner)
    allow(runner).to receive(:call) do
      IkasCatalogSnapshot.last.update!(status: :completed, completed_at: Time.current, sqlite_path: Rails.root.join('tmp/test.sqlite3').to_s)
    end

    described_class.perform_now(hook.id)

    snapshot = hook.ikas_catalog_snapshots.last
    expect(snapshot).to be_completed
    expect(snapshot.account).to eq(account)
    expect(snapshot.store_host).to eq('test-store.myikas.com')
    expect(runner).to have_received(:call)
  end

  it 'does not start a second sync while a fresh sync is active' do
    create(:ikas_catalog_snapshot, account: account, integrations_hook: hook, status: :syncing, started_at: 5.minutes.ago)
    allow(Integrations::Ikas::Catalog::SyncRunner).to receive(:new)

    described_class.perform_now(hook.id)

    expect(hook.ikas_catalog_snapshots.count).to eq(1)
    expect(Integrations::Ikas::Catalog::SyncRunner).not_to have_received(:new)
  end

  it 'does not sync when encryption is unavailable' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(false)
    allow(Integrations::Ikas::Catalog::SyncRunner).to receive(:new)

    described_class.perform_now(hook.id)

    expect(hook.ikas_catalog_snapshots.count).to eq(0)
    expect(Integrations::Ikas::Catalog::SyncRunner).not_to have_received(:new)
  end

  it 'marks stale syncs failed before starting a new sync' do
    stale = create(:ikas_catalog_snapshot, account: account, integrations_hook: hook, status: :syncing, started_at: 1.hour.ago)
    runner = instance_double(Integrations::Ikas::Catalog::SyncRunner, call: true)
    allow(Integrations::Ikas::Catalog::SyncRunner).to receive(:new).and_return(runner)

    described_class.perform_now(hook.id)

    expect(stale.reload).to be_failed
    expect(hook.ikas_catalog_snapshots.count).to eq(2)
  end
end
