require 'rails_helper'
require 'tmpdir'
require Rails.root.join('lib/integrations/ikas/catalog')

RSpec.describe Integrations::Ikas::CatalogSearchService do
  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, :ikas, account: account) }

  before do
    Integrations::Hook.name
    allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    account.enable_features('ikas_integration')
    account.save!
    hook
  end

  def write_jsonl(raw_dir, name, rows)
    File.open(File.join(raw_dir, "#{name}.jsonl"), 'w') do |file|
      rows.each { |row| file.puts(JSON.generate(row)) }
    end
  end

  def build_catalog
    Dir.mktmpdir do |dir|
      raw_dir = File.join(dir, 'raw')
      FileUtils.mkdir_p(raw_dir)
      write_jsonl(raw_dir, 'categories', categories)
      write_jsonl(raw_dir, 'variant_types', variant_types)
      write_jsonl(raw_dir, 'product_attributes', product_attributes)
      write_jsonl(raw_dir, 'product_option_sets', product_option_sets)
      write_jsonl(raw_dir, 'storefronts', storefronts)
      write_jsonl(raw_dir, 'products', products)
      sqlite_path = File.join(dir, 'catalog.sqlite3')
      Integrations::Ikas::Catalog::SqliteBuilder.new(snapshot_dir: dir, sqlite_path: sqlite_path).build
      yield sqlite_path
    end
  end

  def categories
    [
      { 'id' => 'sineklik-root', 'name' => 'Sineklikler', 'parentId' => nil },
      { 'id' => 'sineklik-kedi', 'name' => 'Kedi Sineklikleri', 'parentId' => 'sineklik-root' },
      { 'id' => 'shirts', 'name' => 'Shirts', 'parentId' => nil },
      { 'id' => 'honey', 'name' => 'Honey', 'parentId' => nil },
      { 'id' => 'curtains', 'name' => 'Perdeler', 'parentId' => nil },
      { 'id' => 'blackout', 'name' => 'Blackout', 'parentId' => 'curtains' }
    ]
  end

  def variant_types
    [
      {
        'id' => 'size-type',
        'name' => 'Size',
        'values' => [{ 'id' => 'size-m', 'name' => 'M' }]
      },
      {
        'id' => 'color-type',
        'name' => 'Color',
        'values' => [{ 'id' => 'black', 'name' => 'Black' }]
      }
    ]
  end

  def product_attributes
    [
      { 'id' => 'organic-attr', 'name' => 'Organic', 'type' => 'CHOICE', 'options' => [{ 'id' => 'organic-option', 'name' => 'Organic' }] }
    ]
  end

  def product_option_sets
    [
      {
        'id' => 'sineklik-option-set',
        'name' => 'Sineklik Pencere',
        'options' => [
          { 'name' => 'En (CM)', 'type' => 'TEXT', 'textSettings' => { 'max' => 80 } },
          { 'name' => 'Boy (CM)', 'type' => 'TEXT', 'textSettings' => { 'max' => 100 } }
        ]
      }
    ]
  end

  def storefronts
    [
      {
        'id' => 'storefront-public',
        'name' => 'Public Storefront',
        'type' => 'STOREFRONT',
        'status' => 'READY',
        'salesChannelId' => 'sales-channel-public',
        'domains' => [{ 'id' => 'domain-public', 'name' => 'store.example.com', 'isDefault' => true }],
        'routings' => []
      }
    ]
  end

  def products
    [
      product('sineklik', 'Pencere Kedi Sinekliği', ['sineklik-kedi'], option_set_id: 'sineklik-option-set'),
      product(
        'shirt',
        'Cotton Shirt',
        ['shirts'],
        variant_values: [
          { 'variantTypeId' => 'size-type', 'variantValueId' => 'size-m' },
          { 'variantTypeId' => 'color-type', 'variantValueId' => 'black' }
        ]
      ),
      product(
        'honey',
        'Raw Honey 500g',
        ['honey'],
        attributes: [{ 'productAttributeId' => 'organic-attr', 'productAttributeOptionId' => 'organic-option' }]
      ),
      product('blackout', 'Blackout Perde 80x200', ['blackout'])
    ]
  end

  def product(id, name, category_ids, options = {})
    {
      'id' => "p-#{id}",
      'name' => name,
      'categoryIds' => category_ids,
      'productOptionSetId' => options[:option_set_id],
      'salesChannelIds' => ['sales-channel-public'],
      'hiddenSalesChannelIds' => [],
      'metaData' => { 'slug' => id, 'canonicals' => [] },
      'attributes' => options[:attributes] || [],
      'variants' => [
        {
          'id' => "v-#{id}",
          'isActive' => true,
          'sellIfOutOfStock' => false,
          'variantValueIds' => options[:variant_values] || [],
          'prices' => [{ 'sellPrice' => 10.0, 'currencyCode' => 'TRY' }],
          'stocks' => [{ 'stockCount' => 2 }]
        }
      ]
    }.compact
  end

  def create_snapshot(sqlite_path, snapshot_account: account, snapshot_hook: hook, completed_at: Time.current)
    create(
      :ikas_catalog_snapshot,
      account: snapshot_account,
      integrations_hook: snapshot_hook,
      store_host: snapshot_hook.reference_id,
      sqlite_path: sqlite_path,
      status: :completed,
      completed_at: completed_at,
      metadata: { 'engine' => 'ikas_catalog_sqlite_v2', 'catalog_scope' => 'storefront_public' }
    )
  end

  it 'returns catalog_not_ready when there is no completed snapshot' do
    result = described_class.new(account: account, query_text: '70x90 sineklik').call

    expect(result[:status]).to eq('error')
    expect(result[:error_code]).to eq('catalog_not_ready')
  end

  it 'uses the latest completed snapshot and returns structured candidate evidence' do
    build_catalog do |sqlite_path|
      create_snapshot(sqlite_path, completed_at: 1.minute.ago)

      result = described_class.new(account: account, query_text: '70x90 sineklik', limit: 8).call

      expect(result[:status]).to eq('ok')
      expect(result[:result_type]).to eq('show_compatible_candidates')
      expect(result[:candidates].first[:stock]).to include(in_stock: true, sellable: true)
      expect(result[:catalog]).to include(store_host: 'test-store.myikas.com')
    end
  end

  it 'repairs older completed snapshots that are missing the FTS index' do
    build_catalog do |sqlite_path|
      IkasCatalogSnapshot.where(account: account).delete_all
      snapshot = create_snapshot(sqlite_path, completed_at: 1.day.from_now)
      db = SQLite3::Database.new(sqlite_path)
      db.execute('DROP TABLE catalog_items_fts')
      db.close

      service = described_class.new(account: account, query_text: '70x90 sineklik', limit: 8)
      service.send(:repair_fts_index!, snapshot)
      db = SQLite3::Database.new(snapshot.sqlite_path)
      expect(db.get_first_value('SELECT COUNT(*) FROM catalog_items_fts').to_i).to be_positive
      db.close

      result = service.call

      expect(result[:status]).to eq('ok')
      expect(result[:candidates].first[:product_id]).to eq('p-sineklik')
    end
  end

  it 'applies context query text to dimension-only follow-up searches' do
    build_catalog do |sqlite_path|
      create_snapshot(sqlite_path)

      result = described_class.new(account: account, query_text: '70x90', context_query_text: 'sineklik').call

      expect(result[:query]).to eq('sineklik 70x90')
      expect(result[:candidates].first[:product_id]).to eq('p-sineklik')
    end
  end

  it 'supports variant size/color and organic weight searches' do
    build_catalog do |sqlite_path|
      create_snapshot(sqlite_path)

      shirt = described_class.new(account: account, query_text: 'black shirt medium').call
      honey = described_class.new(account: account, query_text: 'organic honey 500g').call
      blackout = described_class.new(account: account, query_text: 'blackout perde 80x200').call

      expect(shirt[:candidates].first[:product_id]).to eq('p-shirt')
      expect(honey[:candidates].first[:product_id]).to eq('p-honey')
      expect(blackout[:candidates].first[:product_id]).to eq('p-blackout')
    end
  end

  it 'does not allow one account to query another account catalog' do
    other_account = create(:account)
    other_account.enable_features('ikas_integration')
    other_account.save!
    other_hook = create(:integrations_hook, :ikas, account: other_account)

    build_catalog do |sqlite_path|
      create_snapshot(sqlite_path, snapshot_account: other_account, snapshot_hook: other_hook)

      result = described_class.new(account: account, query_text: '70x90 sineklik').call

      expect(result[:status]).to eq('error')
      expect(result[:error_code]).to eq('catalog_not_ready')
    end
  end
end
