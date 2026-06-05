# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/ikas_catalog_mvp'

RSpec.describe IkasCatalogMvp::QueryEngine do
  def write_jsonl(raw_dir, name, rows)
    File.open(File.join(raw_dir, "#{name}.jsonl"), 'w') do |file|
      rows.each { |row| file.puts(JSON.generate(row)) }
    end
  end

  def with_snapshot
    Dir.mktmpdir do |dir|
      raw_dir = File.join(dir, 'raw')
      FileUtils.mkdir_p(raw_dir)
      write_fixture(raw_dir)
      sqlite_path = File.join(dir, 'catalog.sqlite3')
      IkasCatalogMvp::SqliteBuilder.new(snapshot_dir: dir, sqlite_path: sqlite_path).build
      yield sqlite_path
    end
  end

  def write_fixture(raw_dir)
    write_jsonl(raw_dir, 'categories', categories)
      write_jsonl(raw_dir, 'variant_types', variant_types)
      write_jsonl(raw_dir, 'product_attributes', product_attributes)
      write_jsonl(raw_dir, 'product_option_sets', product_option_sets)
      write_jsonl(raw_dir, 'storefronts', storefronts)
      write_jsonl(raw_dir, 'products', products)
  end

  def categories
    [
      { 'id' => 'sineklik-root', 'name' => 'Sineklikler', 'parentId' => nil },
      { 'id' => 'sineklik-kedi', 'name' => 'Kedi Sineklikleri', 'parentId' => 'sineklik-root' },
      { 'id' => 'sineklik-akordiyon', 'name' => 'Akordiyon Sineklikler', 'parentId' => 'sineklik-root' },
      { 'id' => 'shirts', 'name' => 'Shirts', 'parentId' => nil },
      { 'id' => 'honey', 'name' => 'Honey', 'parentId' => nil },
      { 'id' => 'curtains', 'name' => 'Perdeler', 'parentId' => nil },
      { 'id' => 'blackout', 'name' => 'Blackout', 'parentId' => 'curtains' },
      { 'id' => 'balcony', 'name' => 'Balkon Ürünleri', 'parentId' => nil },
      { 'id' => 'panel-root', 'name' => 'Panel Ürünleri', 'parentId' => nil },
      { 'id' => 'panel-cases', 'name' => 'Panel Kasaları', 'parentId' => 'panel-root' },
      { 'id' => 'panel-window-cases', 'name' => 'Pencere Kasaları', 'parentId' => 'panel-cases' },
      { 'id' => 'panel-cased-accessories', 'name' => 'Panel Kasalı Aksesuarlar', 'parentId' => 'panel-root' }
    ]
  end

  def variant_types
    [
      {
        'id' => 'size-type',
        'name' => 'Size',
        'selectionType' => 'choice',
        'values' => [{ 'id' => 'size-m', 'name' => 'M' }]
      },
      {
        'id' => 'color-type',
        'name' => 'Color',
        'selectionType' => 'color',
        'values' => [{ 'id' => 'black', 'name' => 'Black' }, { 'id' => 'white', 'name' => 'White' }]
      }
    ]
  end

  def product_attributes
    [
      { 'id' => 'measurement-attr', 'name' => 'Measurement', 'type' => 'TEXT', 'options' => [] },
      { 'id' => 'organic-attr', 'name' => 'Organic', 'type' => 'CHOICE', 'options' => [{ 'id' => 'organic-option', 'name' => 'Organic' }] }
    ]
  end

  def product_option_sets
    [
      {
        'id' => 'sineklik-option-set',
        'name' => 'Sineklik Pencere',
        'options' => [
          { 'name' => 'En (CM)', 'type' => 'TEXT', 'textSettings' => { 'max' => 70 } },
          { 'name' => 'Boy (CM)', 'type' => 'TEXT', 'textSettings' => { 'max' => 130 } }
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
      },
      {
        'id' => 'storefront-b2b',
        'name' => 'B2B Storefront',
        'type' => 'B2B',
        'status' => 'READY',
        'salesChannelId' => 'sales-channel-b2b',
        'domains' => [{ 'id' => 'domain-b2b', 'name' => 'b2b.example.com', 'isDefault' => true }],
        'routings' => []
      }
    ]
  end

  def products
    [
      sineklik_product,
      kedi_sineklik_product,
      shirt_product,
      honey_product,
      blackout_curtain_product,
      option_set_sineklik_product,
      kedi_pencere_sineklik_product,
      panel_window_case_product,
      panel_cased_accessory_product,
      *extra_kedi_sineklik_products,
      false_range_sineklik_product,
      b2b_only_product
    ].map { |product| product.fetch('id') == 'p-b2b-only' ? product : storefront_product(product) }
  end

  def storefront_product(product)
    product.merge(
      'salesChannelIds' => ['sales-channel-public'],
      'hiddenSalesChannelIds' => [],
      'metaData' => {
        'id' => "meta-#{product.fetch('id')}",
        'slug' => product.fetch('id'),
        'canonicals' => []
      }
    )
  end

  def sineklik_product
    {
      'id' => 'p-sineklik-akordiyon',
      'name' => 'Akordiyon Sineklik',
      'categoryIds' => ['sineklik-akordiyon'],
      'attributes' => [{ 'productAttributeId' => 'measurement-attr', 'value' => 'Max 80x100 cm' }],
      'variants' => [
        variant('v-sineklik-akordiyon', price: 450.0, stocks: 3)
      ]
    }
  end

  def kedi_sineklik_product
    {
      'id' => 'p-sineklik-kedi',
      'name' => 'Kedi İçin Sineklik',
      'categoryIds' => ['sineklik-kedi'],
      'attributes' => [],
      'variants' => [
        variant('v-sineklik-kedi', price: 350.0, stocks: 2)
      ]
    }
  end

  def shirt_product
    {
      'id' => 'p-shirt',
      'name' => 'Cotton Shirt',
      'categoryIds' => ['shirts'],
      'attributes' => [],
      'variants' => [
        variant(
          'v-shirt-black-m',
          price: 40.0,
          stocks: 5,
          variant_values: [
            { 'variantTypeId' => 'size-type', 'variantValueId' => 'size-m' },
            { 'variantTypeId' => 'color-type', 'variantValueId' => 'black' }
          ]
        )
      ]
    }
  end

  def honey_product
    {
      'id' => 'p-honey',
      'name' => 'Raw Honey 500g',
      'categoryIds' => ['honey'],
      'attributes' => [{ 'productAttributeId' => 'organic-attr', 'productAttributeOptionId' => 'organic-option' }],
      'variants' => [
        variant('v-honey', price: 18.0, stocks: 20)
      ]
    }
  end

  def blackout_curtain_product
    {
      'id' => 'p-blackout',
      'name' => 'Thermal 100x200',
      'categoryIds' => ['blackout'],
      'attributes' => [],
      'variants' => [
        variant('v-blackout', price: 900.0, stocks: 4)
      ]
    }
  end

  def panel_window_case_product
    {
      'id' => 'p-panel-window-case',
      'name' => 'Panel Window Case',
      'categoryIds' => ['panel-window-cases'],
      'attributes' => [],
      'variants' => [
        variant('v-panel-window-case', price: 30.0, stocks: 4)
      ]
    }
  end

  def panel_cased_accessory_product
    {
      'id' => 'p-panel-cased-accessory',
      'name' => 'Panel Cased Accessory',
      'categoryIds' => ['panel-cased-accessories'],
      'attributes' => [],
      'variants' => [
        variant('v-panel-cased-accessory', price: 10.0, stocks: 4)
      ]
    }
  end

  def option_set_sineklik_product
    {
      'id' => 'p-option-set-sineklik',
      'name' => 'Structured Option Sineklik',
      'productOptionSetId' => 'sineklik-option-set',
      'categoryIds' => ['sineklik-akordiyon'],
      'attributes' => [],
      'variants' => [
        variant('v-option-set-sineklik', price: 14.0, stocks: 8)
      ]
    }
  end

  def kedi_pencere_sineklik_product
    {
      'id' => 'p-kedi-pencere-sineklik',
      'name' => 'Pencere Kedi Sinekliği',
      'productOptionSetId' => 'sineklik-option-set',
      'categoryIds' => ['sineklik-kedi'],
      'attributes' => [],
      'variants' => [
        variant('v-kedi-pencere-sineklik', price: 16.0, stocks: 6)
      ]
    }
  end

  def extra_kedi_sineklik_products
    10.times.map do |index|
      {
        'id' => "p-kedi-extra-#{index}",
        'name' => "Kedi Sineklik Ek #{index}",
        'categoryIds' => ['sineklik-kedi'],
        'attributes' => [],
        'variants' => [
          variant("v-kedi-extra-#{index}", price: 20.0 + index, stocks: 1)
        ]
      }
    end
  end

  def false_range_sineklik_product
    {
      'id' => 'p-false-range-sineklik',
      'name' => 'Menteşeli Pencere Sineklik',
      'description' => 'Internal option ids 4-1467309 are not dimensions.',
      'categoryIds' => ['sineklik-akordiyon'],
      'attributes' => [],
      'variants' => [
        variant('v-false-range-sineklik', price: 12.0, stocks: 8)
      ]
    }
  end

  def b2b_only_product
    {
      'id' => 'p-b2b-only',
      'name' => 'B2B Only Sineklik',
      'categoryIds' => ['sineklik-akordiyon'],
      'salesChannelIds' => ['sales-channel-b2b'],
      'hiddenSalesChannelIds' => [],
      'metaData' => { 'slug' => 'b2b-only-sineklik', 'canonicals' => [] },
      'attributes' => [{ 'productAttributeId' => 'measurement-attr', 'value' => 'Max 80x100 cm' }],
      'variants' => [
        variant('v-b2b-only', price: 1.0, stocks: 10)
      ]
    }
  end

  def variant(id, price:, stocks:, variant_values: [])
    {
      'id' => id,
      'isActive' => true,
      'sellIfOutOfStock' => false,
      'variantValueIds' => variant_values,
      'prices' => [{ 'sellPrice' => price, 'currencyCode' => 'TRY' }],
      'stocks' => [{ 'stockCount' => stocks }],
      'images' => []
    }
  end

  it 'returns clarification buckets for broad category queries' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('sineklik')

      expect(payload.fetch('result_type')).to eq('clarify_category')
      expect(payload.fetch('buckets').map { |bucket| bucket.fetch('label') }).to include('Kedi Sineklikleri', 'Akordiyon Sineklikler')
    end
  end

  it 'prefers the deeper noun category instead of a broad parent when short fuzzy matches would overreach' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('panel kasası')
      product_ids = payload.fetch('candidates').map { |candidate| candidate.fetch('product_id') }

      expect(payload.fetch('matched_scope').fetch('id')).to eq('panel-cases')
      expect(product_ids).to include('p-panel-window-case')
      expect(product_ids).not_to include('p-panel-cased-accessory')
    end
  end

  it 'matches customer dimensions against product max dimensions' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('70x90 sineklik')
      candidate = payload.fetch('candidates').find { |row| row.fetch('display_name').include?('Akordiyon Sineklik') }

      expect(payload.fetch('result_type')).to eq('show_compatible_candidates')
      expect(candidate.fetch('match_reasons')).to include('requested dimensions fit product max dimensions')
      expect(candidate.dig('link', 'url')).to eq('https://store.example.com/p-sineklik-akordiyon')
    end
  end

  it 'requires conversation context for dimension-only follow-up queries' do
    with_snapshot do |sqlite_path|
      engine = described_class.new(sqlite_path: sqlite_path)

      expect(engine.context_required_for?('70x80')).to be(true)
      expect(engine.context_required_for?('70x80 link fiyat')).to be(true)
      expect(engine.context_required_for?('akordiyon sineklik 70x80')).to be(false)
      expect(engine.context_required_for?('blackout perde 70x80')).to be(false)
    end
  end

  it 'asks for product scope instead of searching all dimension-compatible products' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('70x80')

      expect(payload.fetch('result_type')).to eq('needs_scope')
      expect(payload.fetch('next_action')).to eq('ask_customer_which_product_or_category')
      expect(payload.fetch('candidates')).to eq([])
    end
  end

  it 'uses the latest catalog-scoped context without carrying old constraints' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query(
        '70x80',
        context_texts: ['sineklik var mi', 'akordiyon sineklikler', '70x100 olsun link ve fiyat verir misin']
      )
      product_ids = payload.fetch('candidates').map { |candidate| candidate.fetch('product_id') }

      expect(payload.fetch('query')).to eq('akordiyon sineklikler 70x80')
      expect(payload.fetch('result_type')).to eq('show_compatible_candidates')
      expect(product_ids).to include('p-sineklik-akordiyon')
      expect(payload.fetch('query')).not_to include('70x100')
    end
  end

  it 'handles apparel size and color variants generically' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('black m shirt')

      expect(payload.fetch('result_type')).to eq('show_candidates')
      expect(payload.fetch('candidates').first.fetch('variant_id')).to eq('v-shirt-black-m')
      expect(payload.fetch('candidates').first.fetch('match_reasons')).to include('matched size', 'matched color')
      expect(payload.dig('candidates', 0, 'link', 'url')).to include('%22Size%22=M', '%22Color%22=Black')
    end
  end

  it 'handles organic food and weight constraints generically' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('organic honey 500g')

      expect(payload.fetch('result_type')).to eq('show_candidates')
      expect(payload.fetch('candidates').first.fetch('product_id')).to eq('p-honey')
      expect(payload.fetch('candidates').first.fetch('match_reasons')).to include('catalog indicates organic or natural product', 'matched weight')
    end
  end

  it 'handles Turkish organic wording without leaving it as a search term' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('doğal honey 500g')

      expect(payload.fetch('result_type')).to eq('show_candidates')
      expect(payload.fetch('parsed').fetch('terms')).to eq(['honey'])
      expect(payload.fetch('candidates').first.fetch('product_id')).to eq('p-honey')
    end
  end

  it 'matches products by category path when product names do not repeat the category' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('blackout perde')

      expect(payload.fetch('result_type')).to eq('show_candidates')
      expect(payload.fetch('matched_scope').fetch('id')).to eq('blackout')
      expect(payload.fetch('candidates').first.fetch('product_id')).to eq('p-blackout')
    end
  end

  it 'does not match short product terms against longer unrelated category words' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('bal')

      expect(payload.fetch('matched_scope')).to be_nil
    end
  end

  it 'uses a matched main category as the search scope without requiring title text' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('honey')

      expect(payload.fetch('result_type')).to eq('show_candidates')
      expect(payload.fetch('matched_scope').fetch('id')).to eq('honey')
      expect(payload.fetch('candidates').first.fetch('product_id')).to eq('p-honey')
    end
  end

  it 'does not treat unitless numeric ranges as dimensions' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('70x90 sineklik', limit: 10)

      product_ids = payload.fetch('candidates').map { |candidate| candidate.fetch('product_id') }
      expect(product_ids).not_to include('p-false-range-sineklik')
    end
  end

  it 'does not index products that are not visible on a public storefront' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('b2b only sineklik', limit: 10)
      product_ids = payload.fetch('candidates').map { |candidate| candidate.fetch('product_id') }

      expect(product_ids).not_to include('p-b2b-only')
    end
  end

  it 'matches dimensions from structured product option sets' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('70x90 structured option sineklik', limit: 10)
      candidate = payload.fetch('candidates').find { |row| row.fetch('product_id') == 'p-option-set-sineklik' }

      expect(candidate.fetch('match_reasons')).to include('requested dimensions fit product max dimensions')
      expect(candidate.fetch('evidence').first.fetch('source')).to eq('product_option_set')
    end
  end

  it 'does not use custom size fallback when known max dimensions are exceeded' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('80x140 structured option sineklik', limit: 10)
      product_ids = payload.fetch('candidates').map { |candidate| candidate.fetch('product_id') }

      expect(product_ids).not_to include('p-option-set-sineklik')
    end
  end

  it 'keeps Turkish singular and plural category wording aligned for scoped searches' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('kedi için pencere sinekliği 70x90', limit: 10)
      product_ids = payload.fetch('candidates').map { |candidate| candidate.fetch('product_id') }

      expect(product_ids).to include('p-kedi-pencere-sineklik')
    end
  end

  it 'keeps a substantial matching subtype as the clarification scope' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('kedi için sineklik')

      expect(payload.fetch('matched_scope').fetch('id')).to eq('sineklik-kedi')
    end
  end
end
