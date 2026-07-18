# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require_relative '../../../lib/ikas_catalog_mvp'

RSpec.describe IkasCatalogMvp::SqliteBuilder do
  def write_jsonl(raw_dir, name, rows)
    File.open(File.join(raw_dir, "#{name}.jsonl"), 'w') do |file|
      rows.each { |row| file.puts(JSON.generate(row)) }
    end
  end

  def build_catalog(products: self.products)
    Dir.mktmpdir do |dir|
      raw_dir = File.join(dir, 'raw')
      FileUtils.mkdir_p(raw_dir)
      write_jsonl(raw_dir, 'merchants', [{ 'id' => '05d8a2b7-89af-41b3-b47f-b091868cfd8c' }])
      write_jsonl(raw_dir, 'categories', [])
      write_jsonl(raw_dir, 'variant_types', [])
      write_jsonl(raw_dir, 'product_attributes', [])
      write_jsonl(raw_dir, 'product_option_sets', [])
      write_jsonl(raw_dir, 'storefronts', storefronts)
      write_jsonl(raw_dir, 'products', products)

      sqlite_path = File.join(dir, 'catalog.sqlite3')
      IkasCatalogMvp::SqliteBuilder.new(snapshot_dir: dir, sqlite_path: sqlite_path).build
      yield sqlite_path
    end
  end

  it 'stores ordered non-video images and exposes compact image availability to search' do
    build_catalog do |sqlite_path|
      db = SQLite3::Database.new(sqlite_path)
      db.results_as_hash = true
      rows = db.execute('SELECT item_id, image_id, canonical_url, is_main, position, image_scope FROM catalog_item_images ORDER BY position')

      expect(rows).to contain_exactly(
        include(
          'item_id' => 'variant:variant-1',
          'image_id' => '5a9ebce4-8b06-4b92-9ed2-a8ffadb435de',
          'canonical_url' => 'https://cdn.myikas.com/images/05d8a2b7-89af-41b3-b47f-b091868cfd8c/5a9ebce4-8b06-4b92-9ed2-a8ffadb435de/1080/main%20image.webp',
          'is_main' => 1,
          'position' => 0,
          'image_scope' => 'variant'
        ),
        include(
          'item_id' => 'variant:variant-1',
          'image_id' => '4d02aeeb-f07c-4c29-8f90-b44511fe32db',
          'canonical_url' => 'https://cdn.myikas.com/images/05d8a2b7-89af-41b3-b47f-b091868cfd8c/4d02aeeb-f07c-4c29-8f90-b44511fe32db/1080/second%20image.webp',
          'is_main' => 0,
          'position' => 1,
          'image_scope' => 'variant'
        )
      )

      candidate = IkasCatalogMvp::QueryEngine.new(sqlite_path: sqlite_path).query('Balcony screen').fetch('candidates').first
      expect(candidate.fetch('image')).to eq('available' => true, 'count' => 2, 'scope' => 'variant')
      expect(candidate.to_json).not_to include('cdn.myikas.com', 'main-image.webp')
    ensure
      db&.close
    end
  end

  it 'uses a usable active-variant image when the exact variant has no valid still image' do
    variants = [
      variant('video-only', images: [{
                'imageId' => '49c3d09c-a4c2-4352-b6c3-0352651e3883', 'fileName' => 'demo', 'isVideo' => true
              }]),
      variant('inactive', active: false, images: [{
                'imageId' => '6fa399f1-f8d4-4371-ac1c-8dd55f388543', 'fileName' => 'inactive'
              }]),
      variant('usable', images: [{
                'imageId' => '1813a270-8ce1-48ef-a25b-bdeba1c4dc06', 'fileName' => 'usable'
              }])
    ]
    product = products.first.merge('variants' => variants)

    build_catalog(products: [product]) do |sqlite_path|
      db = SQLite3::Database.new(sqlite_path)
      db.results_as_hash = true
      rows = db.execute('SELECT item_id, image_id, image_scope FROM catalog_item_images ORDER BY item_id')

      expect(rows).to contain_exactly(
        include(
          'item_id' => 'variant:usable',
          'image_id' => '1813a270-8ce1-48ef-a25b-bdeba1c4dc06',
          'image_scope' => 'variant'
        ),
        include(
          'item_id' => 'variant:video-only',
          'image_id' => '1813a270-8ce1-48ef-a25b-bdeba1c4dc06',
          'image_scope' => 'representative_product'
        )
      )
    ensure
      db&.close
    end
  end

  def storefronts
    [{
      'id' => 'storefront-public',
      'name' => 'Public Storefront',
      'type' => 'STOREFRONT',
      'status' => 'READY',
      'salesChannelId' => 'sales-channel-public',
      'domains' => [{ 'id' => 'domain-public', 'name' => 'store.example.com', 'isDefault' => true }],
      'routings' => []
    }]
  end

  def products
    [{
      'id' => 'product-1',
      'name' => 'Balcony Screen',
      'categoryIds' => [],
      'salesChannelIds' => ['sales-channel-public'],
      'hiddenSalesChannelIds' => [],
      'metaData' => { 'slug' => 'balcony-screen', 'canonicals' => [] },
      'attributes' => [],
      'variants' => [{
        'id' => 'variant-1',
        'isActive' => true,
        'variantValueIds' => [],
        'prices' => [{ 'sellPrice' => 499, 'currencyCode' => 'TRY' }],
        'stocks' => [{ 'stockCount' => 5 }],
        'images' => product_images
      }]
    }]
  end

  def product_images
    [
      { 'imageId' => '4d02aeeb-f07c-4c29-8f90-b44511fe32db', 'fileName' => 'second image', 'isMain' => false, 'isVideo' => false, 'order' => 1 },
      { 'imageId' => 'video-id', 'fileName' => 'demo-video', 'isMain' => false, 'isVideo' => true, 'order' => 0 },
      { 'imageId' => '5a9ebce4-8b06-4b92-9ed2-a8ffadb435de', 'fileName' => 'main image', 'isMain' => true, 'isVideo' => false, 'order' => 2 }
    ]
  end

  def variant(id, images:, active: true)
    {
      'id' => id,
      'isActive' => active,
      'variantValueIds' => [],
      'prices' => [{ 'sellPrice' => 499, 'currencyCode' => 'TRY' }],
      'stocks' => [{ 'stockCount' => 5 }],
      'images' => images
    }
  end
end
