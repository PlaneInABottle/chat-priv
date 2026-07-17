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
      { 'id' => 'sineklik-kedi-door', 'name' => 'Kedi Tüllü Kapı Sineklikleri', 'parentId' => 'sineklik-kedi' },
      { 'id' => 'sineklik-akordiyon', 'name' => 'Akordiyon Sineklikler', 'parentId' => 'sineklik-root' },
      { 'id' => 'sineklik-akordiyon-door', 'name' => 'Akordiyon Kapı Sineklikleri', 'parentId' => 'sineklik-akordiyon' },
      { 'id' => 'sineklik-hinged', 'name' => 'Menteşeli Sineklikler', 'parentId' => 'sineklik-root' },
      { 'id' => 'sineklik-hinged-door', 'name' => 'Menteşeli Kapı Sineklikleri', 'parentId' => 'sineklik-hinged' },
      { 'id' => 'sineklik-hinged-window', 'name' => 'Menteşeli Pencere Sinekliği', 'parentId' => 'sineklik-hinged' },
      { 'id' => 'sineklik-balcony', 'name' => 'Cam Balkon Sineklikleri', 'parentId' => 'sineklik-root' },
      { 'id' => 'shirts', 'name' => 'Shirts', 'parentId' => nil },
      { 'id' => 'honey', 'name' => 'Honey', 'parentId' => nil },
      { 'id' => 'curtains', 'name' => 'Perdeler', 'parentId' => nil },
      { 'id' => 'plise-curtains', 'name' => 'Plise Perdeler', 'parentId' => 'curtains' },
      { 'id' => 'blackout', 'name' => 'Blackout Plise Perdeler', 'parentId' => 'plise-curtains' },
      { 'id' => 'dimout', 'name' => 'Dimout Plise Perdeler', 'parentId' => 'plise-curtains' },
      { 'id' => 'separator-curtains', 'name' => 'Seperatör Kapılar', 'parentId' => 'curtains' },
      { 'id' => 'balcony', 'name' => 'Balkon Ürünleri', 'parentId' => nil },
      { 'id' => 'panel-root', 'name' => 'Panel Ürünleri', 'parentId' => nil },
      { 'id' => 'panel-cases', 'name' => 'Panel Kasaları', 'parentId' => 'panel-root' },
      { 'id' => 'panel-window-cases', 'name' => 'Pencere Kasaları', 'parentId' => 'panel-cases' },
      { 'id' => 'panel-cased-accessories', 'name' => 'Panel Kasalı Aksesuarlar', 'parentId' => 'panel-root' },
      { 'id' => 'home-root', 'name' => 'Home Goods', 'parentId' => nil },
      { 'id' => 'rain-covers', 'name' => 'Rain Covers', 'parentId' => 'home-root' },
      { 'id' => 'doors', 'name' => 'Doors', 'parentId' => nil }
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
        'values' => [{ 'id' => 'black', 'name' => 'Black' }, { 'id' => 'white', 'name' => 'White' }, { 'id' => 'beyaz', 'name' => 'Beyaz' }]
      },
      {
        'id' => 'curtain-color-type',
        'name' => 'Perde Rengi',
        'selectionType' => 'choice',
        'values' => [{ 'id' => 'curtain-beyaz', 'name' => 'Beyaz Perde' }]
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
      },
      {
        'id' => 'wide-door-option-set',
        'name' => 'Wide Door',
        'options' => [
          { 'name' => 'Width (CM)', 'type' => 'TEXT', 'textSettings' => { 'max' => 125 } },
          { 'name' => 'Height (CM)', 'type' => 'TEXT', 'textSettings' => { 'max' => 240 } }
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
        'routings' => [{ 'domain' => 'store.example.com', 'path' => nil, 'currencyCode' => 'TRY', 'currencySymbol' => '₺' }]
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
      hinged_door_sineklik_product,
      hinged_window_sineklik_product,
      shirt_product,
      white_shirt_product,
      honey_product,
      currency_fallback_product,
      blackout_curtain_product,
      dimout_curtain_product,
      plise_color_curtain_product,
      separator_curtain_product,
      structured_color_curtain_product,
      title_color_curtain_product,
      option_set_sineklik_product,
      kedi_pencere_sineklik_product,
      panel_window_case_product,
      panel_cased_accessory_product,
      nested_category_product,
      conflicting_dimension_product,
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
      'categoryIds' => ['sineklik-akordiyon-door'],
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
      'categoryIds' => ['sineklik-kedi-door'],
      'attributes' => [],
      'variants' => [
        variant('v-sineklik-kedi', price: 350.0, stocks: 2)
      ]
    }
  end

  def hinged_door_sineklik_product
    {
      'id' => 'p-sineklik-hinged-door',
      'name' => 'Menteşeli Kapı Sineklik',
      'categoryIds' => ['sineklik-hinged-door'],
      'attributes' => [],
      'variants' => [
        variant('v-sineklik-hinged-door', price: 390.0, stocks: 3)
      ]
    }
  end

  def hinged_window_sineklik_product
    {
      'id' => 'p-sineklik-hinged-window',
      'name' => 'Menteşeli Pencere Sineklik',
      'categoryIds' => ['sineklik-hinged-window'],
      'attributes' => [],
      'variants' => [
        variant('v-sineklik-hinged-window', price: 310.0, stocks: 3)
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

  def white_shirt_product
    {
      'id' => 'p-white-shirt',
      'name' => 'White Cotton Shirt',
      'categoryIds' => ['shirts'],
      'attributes' => [],
      'variants' => [
        variant(
          'v-white-shirt',
          price: 45.0,
          stocks: 5,
          variant_values: [
            { 'variantTypeId' => 'color-type', 'variantValueId' => 'beyaz' }
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
        variant('v-honey', price: 18.0, discount_price: 15.0, stocks: 20)
      ]
    }
  end

  def currency_fallback_product
    {
      'id' => 'p-currency-fallback',
      'name' => 'Currency Fallback Honey 250g',
      'categoryIds' => ['honey'],
      'attributes' => [],
      'variants' => [
        variant('v-currency-fallback', price: 22.0, stocks: 8, currency_code: nil)
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

  def dimout_curtain_product
    {
      'id' => 'p-dimout',
      'name' => 'Dimout Katlanır Perde',
      'categoryIds' => ['dimout'],
      'attributes' => [],
      'variants' => [
        variant('v-dimout', price: 650.0, stocks: 4)
      ]
    }
  end

  def separator_curtain_product
    {
      'id' => 'p-separator',
      'name' => 'Seperatör Kapı Perdesi',
      'categoryIds' => ['separator-curtains'],
      'attributes' => [],
      'variants' => [
        variant('v-separator', price: 1200.0, stocks: 4)
      ]
    }
  end

  def plise_color_curtain_product
    {
      'id' => 'p-plise-color-curtain',
      'name' => 'Generic Plise Perde',
      'categoryIds' => ['plise-curtains'],
      'attributes' => [],
      'variants' => [
        variant(
          'v-plise-color-curtain',
          price: 720.0,
          stocks: 5,
          variant_values: [
            { 'variantTypeId' => 'curtain-color-type', 'variantValueId' => 'curtain-beyaz' }
          ]
        )
      ]
    }
  end

  def title_color_curtain_product
    {
      'id' => 'p-title-color-curtain',
      'name' => 'Orjin Pliseli Perde Beyaz',
      'categoryIds' => ['curtains'],
      'attributes' => [],
      'variants' => [
        variant('v-title-color-curtain', price: 750.0, stocks: 5)
      ]
    }
  end

  def structured_color_curtain_product
    {
      'id' => 'p-structured-color-curtain',
      'name' => 'Orjin Pliseli Perde',
      'categoryIds' => ['curtains'],
      'attributes' => [],
      'variants' => [
        variant(
          'v-structured-color-curtain',
          price: 760.0,
          stocks: 5,
          variant_values: [
            { 'variantTypeId' => 'curtain-color-type', 'variantValueId' => 'curtain-beyaz' }
          ]
        )
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

  def nested_category_product
    {
      'id' => 'p-nested-category',
      'name' => 'Clear Cover',
      'categoryIds' => ['rain-covers'],
      'attributes' => [],
      'variants' => [
        variant('v-nested-category', price: 12.0, stocks: 6)
      ]
    }
  end

  def conflicting_dimension_product
    {
      'id' => 'p-conflicting-dimension',
      'name' => 'Custom Door Max 110x240 cm',
      'productOptionSetId' => 'wide-door-option-set',
      'categoryIds' => ['doors'],
      'attributes' => [],
      'variants' => [
        variant('v-conflicting-dimension', price: 100.0, stocks: 3)
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

  def variant(id, price:, stocks:, variant_values: [], discount_price: nil, currency_code: 'TRY')
    {
      'id' => id,
      'isActive' => true,
      'sellIfOutOfStock' => false,
      'variantValueIds' => variant_values,
      'prices' => [{ 'sellPrice' => price, 'discountPrice' => discount_price, 'currencyCode' => currency_code }],
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

  it 'includes one level of nested category buckets for broad clarification responses' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('perde')
      plise_bucket = payload.fetch('buckets').find { |bucket| bucket.fetch('label') == 'Plise Perdeler' }

      expect(payload.fetch('result_type')).to eq('clarify_category')
      expect(payload.fetch('matched_scope').fetch('id')).to eq('curtains')
      expect(payload.fetch('buckets').map { |bucket| bucket.fetch('label') }).to include('Plise Perdeler', 'Seperatör Kapılar')
      expect(plise_bucket.fetch('children').map { |bucket| bucket.fetch('label') }).to include('Blackout Plise Perdeler', 'Dimout Plise Perdeler')
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

  it 'asks for product scope instead of searching all dimension-compatible products' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('70x80')

      expect(payload.fetch('result_type')).to eq('needs_scope')
      expect(payload.fetch('next_action')).to eq('ask_customer_which_product_or_category')
      expect(payload.fetch('candidates')).to eq([])
    end
  end

  it 'caches selective item-scope lookups within a query' do
    engine = described_class.new(sqlite_path: 'unused.sqlite3')
    db = instance_double(SQLite3::Database)
    allow(db).to receive(:get_first_value) do |sql, *_bindings|
      sql.include?('WHERE search_text_folded') ? 3 : 100
    end
    engine.instance_variable_set(:@query_cache, {})

    2.times { engine.send(:selective_item_scope_term?, db, 'sineklik') }

    expect(db).to have_received(:get_first_value).twice
  end

  it 'matches multiple catalog-declared variant facets' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('black m shirt')

      expect(payload.fetch('result_type')).to eq('show_candidates')
      expect(payload.fetch('candidates').first.fetch('variant_id')).to eq('v-shirt-black-m')
      expect(payload.fetch('candidates').first.fetch('match_reasons')).to include('matched facet')
      expect(payload.dig('candidates', 0, 'link', 'url')).to include('%22Size%22=M', '%22Color%22=Black')
    end
  end

  it 'handles organic food and weight constraints generically' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('organic honey 500g')

      expect(payload.fetch('result_type')).to eq('show_candidates')
      expect(payload.fetch('candidates').first.fetch('product_id')).to eq('p-honey')
      expect(payload.fetch('candidates').first.fetch('match_reasons')).to include('matched facet', 'matched weight')
    end
  end

  it 'uses discounted prices as current prices while preserving compare-at prices' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('organic honey 500g')
      price = payload.fetch('candidates').first.fetch('price')

      expect(price).to include(
        'amount' => 15.0,
        'compare_at_amount' => 18.0,
        'currency' => 'TRY',
        'final_total_known' => true,
        'pricing_model' => 'fixed'
      )
    end
  end

  it 'falls back to storefront routing currency when a price row omits currency' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('currency fallback honey 250g')
      price = payload.fetch('candidates').first.fetch('price')

      expect(price).to include(
        'amount' => 22.0,
        'currency' => 'TRY',
        'final_total_known' => true,
        'pricing_model' => 'fixed'
      )
    end
  end

  it 'matches products by category path when product names do not repeat the category' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('blackout perde')

      expect(payload.fetch('result_type')).to eq('show_candidates')
      expect(payload.fetch('matched_scope').fetch('id')).to eq('blackout')
      expect(payload.fetch('candidates').first.fetch('product_id')).to eq('p-blackout')
      expect(payload.fetch('candidates').first.fetch('category_paths')).to include('Perdeler > Plise Perdeler > Blackout Plise Perdeler')
    end
  end

  it 'matches products through ancestor category names' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('home clear cover')

      expect(payload.fetch('result_type')).to eq('show_candidates')
      expect(payload.fetch('candidates').first.fetch('product_id')).to eq('p-nested-category')
      expect(payload.fetch('candidates').first.fetch('category_paths')).to include('Home Goods > Rain Covers')
    end
  end

  it 'matches color constraints from the product title when Ikas has no structured color facet' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('beyaz perde')
      candidate = payload.fetch('candidates').find { |row| row.fetch('product_id') == 'p-title-color-curtain' }

      expect(payload.fetch('result_type')).to eq('show_candidates')
      expect(candidate.fetch('match_reasons')).to include('matched facet')
      expect(candidate.fetch('evidence').first.fetch('source')).to eq('display_name')
    end
  end

  it 'ranks structured variant evidence above title-only fallback evidence' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('beyaz perde')
      candidates = payload.fetch('candidates')
      structured = candidates.find { |row| row.fetch('product_id') == 'p-structured-color-curtain' }
      title_only = candidates.find { |row| row.fetch('product_id') == 'p-title-color-curtain' }

      expect(candidates.first.fetch('product_id')).not_to eq('p-title-color-curtain')
      expect(structured.fetch('relevance_score')).to be > title_only.fetch('relevance_score')
      expect(structured.fetch('relevance_signals').map { |signal| signal.fetch('kind') }).to include('structured_evidence_match')
      expect(title_only.fetch('relevance_signals').map { |signal| signal.fetch('kind') }).to include('fallback_evidence_match')
    end
  end

  it 'does not match short product terms against longer unrelated category words' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('bal')

      expect(payload.fetch('matched_scope')).to be_nil
      expect(payload.fetch('candidates')).to be_empty
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

  it 'uses the tightest compatible max dimension when multiple max facts fit' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('90x210 custom door', limit: 10)
      candidate = payload.fetch('candidates').find { |row| row.fetch('product_id') == 'p-conflicting-dimension' }
      dimension_evidence = candidate.fetch('evidence').find { |row| row.fetch('fact') == 'dimension_max' }

      expect(dimension_evidence).to include(
        'value' => '110.0x240.0',
        'source' => 'text'
      )
    end
  end

  it 'marks custom option prices as reference prices instead of final totals' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('70x90 structured option sineklik', limit: 10)
      candidate = payload.fetch('candidates').find { |row| row.fetch('product_id') == 'p-option-set-sineklik' }

      expect(candidate.fetch('price')).to include(
        'amount' => nil,
        'reference_amount' => 14.0,
        'final_total_known' => false,
        'pricing_model' => 'custom_options'
      )
    end
  end

  it 'uses non-facet terms for category scoping when the query contains color constraints' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('plise perde beyaz', limit: 10)
      product_ids = payload.fetch('candidates').map { |candidate| candidate.fetch('product_id') }

      expect(payload.fetch('matched_scope').fetch('id')).to eq('plise-curtains')
      expect(product_ids).to include('p-plise-color-curtain')
      expect(product_ids).not_to include('p-separator')
    end
  end

  it 'does not use custom size fallback when known max dimensions are exceeded' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('80x140 structured option sineklik', limit: 10)
      product_ids = payload.fetch('candidates').map { |candidate| candidate.fetch('product_id') }

      expect(product_ids).not_to include('p-option-set-sineklik')
    end
  end

  it 'matches concise catalog scope terms with structured dimensions' do
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

  it 'asks for the exact smaller category buckets for a broad subtype query' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('menteşeli sineklik')

      expect(payload.fetch('result_type')).to eq('clarify_category')
      expect(payload.fetch('matched_scope').fetch('id')).to eq('sineklik-hinged')
      expect(payload.fetch('buckets').map { |bucket| bucket.fetch('label') }).to include(
        'Menteşeli Kapı Sineklikleri',
        'Menteşeli Pencere Sinekliği'
      )
    end
  end

  it 'prefers an exact smaller multi-word category over the broad parent' do
    with_snapshot do |sqlite_path|
      engine = described_class.new(sqlite_path: sqlite_path)

      expect(engine.query('cam balkon sineklik').fetch('matched_scope').fetch('id')).to eq('sineklik-balcony')
      expect(engine.query('menteşeli kapı sinekliği').fetch('matched_scope').fetch('id')).to eq('sineklik-hinged-door')
    end
  end

  it 'relaxes over-specific catalog phrases without language-specific rewrites' do
    with_snapshot do |sqlite_path|
      engine = described_class.new(sqlite_path: sqlite_path)
      cases = {
        'balkon kapısı kedi tüllü sineklik' => 'p-sineklik-kedi',
        'akordiyon sineklik balkon kapısı' => 'p-sineklik-akordiyon',
        'menteşeli sineklik balkon kapısı' => 'p-sineklik-hinged-door'
      }

      aggregate_failures do
        cases.each do |query, product_id|
          payload = engine.query(query)

          expect(payload.fetch('result_type')).to eq('show_candidates')
          expect(payload.fetch('candidates').map { |candidate| candidate.fetch('product_id') }).to include(product_id)
          expect(payload.dig('parsed', 'terms')).to include('balkon')
        end
      end
    end
  end

  it 'does not relax a query when only half of its terms match' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('mor sineklik')

      expect(payload.fetch('result_type')).to eq('no_match')
      expect(payload.fetch('candidates')).to be_empty
    end
  end

  it 'parses free-form words without static language dictionaries' do
    parsed = IkasCatalogMvp::QueryParser.new.parse('show available organic product')

    expect(parsed.fetch('terms')).to contain_exactly('show', 'available', 'organic', 'product')
    expect(parsed.fetch('constraints')).to be_empty
    expect(parsed.fetch('unsupported_constraints')).to be_empty
  end

  it 'uses cautious fuzzy matching for catalog scope typos' do
    with_snapshot do |sqlite_path|
      engine = described_class.new(sqlite_path: sqlite_path)

      expect(engine.query('cam balkom sineklik').fetch('matched_scope').fetch('id')).to eq('sineklik-balcony')
      expect(engine.query('akordeon sineklik 70x80').fetch('matched_scope').fetch('id')).to eq('sineklik-akordiyon')
      expect(engine.query('sineklk').fetch('matched_scope').fetch('id')).to eq('sineklik-root')
      expect(engine.query('bal').fetch('matched_scope')).to be_nil
    end
  end

  it 'does not treat a short shared prefix as a category match' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('mental sineklik')

      expect(payload.dig('matched_scope', 'id')).not_to eq('sineklik-hinged')
    end
  end

  it 'does not remove purchase quantity words through a static dictionary' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('70x90 sineklik 2 tane')

      expect(payload.fetch('result_type')).to eq('no_match')
      expect(payload.fetch('parsed').fetch('terms')).to include('tane')
    end
  end

  it 'builds a full-text search index for catalog items' do
    with_snapshot do |sqlite_path|
      db = SQLite3::Database.new(sqlite_path)
      count = db.get_first_value('SELECT COUNT(*) FROM catalog_items_fts').to_i

      expect(count).to be_positive
    ensure
      db&.close
    end
  end

  it 'retrieves text candidates through FTS5 while keeping structured ranking' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('cotton shirt')
      candidate = payload.fetch('candidates').first
      fts_signal = candidate.fetch('relevance_signals').find { |signal| signal.fetch('kind') == 'fts_bm25_match' }

      expect(payload.fetch('search_backend')).to eq('fts5')
      expect(candidate.fetch('product_id')).to eq('p-shirt')
      expect(fts_signal.fetch('raw_score')).to be_positive
      expect(fts_signal.fetch('score')).to be_between(1, 20)
      expect(candidate.fetch('relevance_signals').map { |signal| signal.fetch('kind') }).not_to include('title_term_match', 'search_text_term_match')
    end
  end

  it 'keeps realistic product searches working through FTS5' do
    with_snapshot do |sqlite_path|
      engine = described_class.new(sqlite_path: sqlite_path)

      expect(engine.query('blackout perde').fetch('candidates').first.fetch('product_id')).to eq('p-blackout')
      expect(engine.query('akordeon sineklik 70x80').fetch('candidates').map { |row| row.fetch('product_id') }).to include('p-sineklik-akordiyon')
      expect(engine.query('beyaz perdeler').fetch('candidates').map { |row| row.fetch('product_id') }).to include(
        'p-structured-color-curtain',
        'p-title-color-curtain'
      )
    end
  end

  it 'supports prefix retrieval through FTS5 for partial product words' do
    with_snapshot do |sqlite_path|
      payload = described_class.new(sqlite_path: sqlite_path).query('plise perd')
      product_ids = payload.fetch('candidates').map { |row| row.fetch('product_id') }

      expect(product_ids).to include('p-title-color-curtain')
      expect(payload.fetch('candidates').first.fetch('relevance_signals').map { |signal| signal.fetch('kind') }).to include('fts_bm25_match')
    end
  end

  it 'requires a resynced catalog when FTS5 is missing for lexical search' do
    with_snapshot do |sqlite_path|
      db = SQLite3::Database.new(sqlite_path)
      db.execute('DROP TABLE catalog_items_fts')
      db.close
      db = nil

      expect { described_class.new(sqlite_path: sqlite_path).query('cotton shirt') }
        .to raise_error(IkasCatalogMvp::Error, 'Ikas catalog FTS index is missing. Sync the catalog again.')
    ensure
      db&.close
    end
  end
end
