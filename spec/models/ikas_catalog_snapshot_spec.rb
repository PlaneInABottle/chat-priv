require 'rails_helper'

RSpec.describe IkasCatalogSnapshot do
  it 'returns the latest completed snapshot first' do
    account = create(:account)
    account.enable_features('ikas_integration')
    account.save!
    hook = create(:integrations_hook, :ikas, account: account)
    older = create(:ikas_catalog_snapshot, account: hook.account, integrations_hook: hook, completed_at: 2.hours.ago)
    newer = create(:ikas_catalog_snapshot, account: hook.account, integrations_hook: hook, completed_at: 1.hour.ago)

    expect(described_class.where(account: hook.account).latest_completed.first).to eq(newer)
    expect(described_class.where(account: hook.account).latest_completed).to include(older)
  end

  it 'checks whether the sqlite artifact exists' do
    snapshot = build(:ikas_catalog_snapshot, sqlite_path: Rails.root.join('tmp/missing_catalog.sqlite3').to_s)

    expect(snapshot.sqlite_exists?).to be false
  end
end
