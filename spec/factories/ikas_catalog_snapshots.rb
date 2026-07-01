# frozen_string_literal: true

FactoryBot.define do
  factory :ikas_catalog_snapshot do
    account
    association :integrations_hook, factory: [:integrations_hook, :ikas]
    store_host { integrations_hook.reference_id }
    status { :completed }
    sqlite_path { Rails.root.join('tmp/test_catalog.sqlite3').to_s }
    counts { { 'products' => 1, 'categories' => 1, 'product_option_sets' => 0, 'catalog_items' => 1 } }
    metadata { { 'engine' => 'ikas_catalog_sqlite_v1' } }
    started_at { 1.minute.ago }
    completed_at { Time.current }
  end
end
