require 'rails_helper'

RSpec.describe Integrations::Ikas::Catalog::ItemImagesResolver do
  let(:account) { create(:account) }

  it 'resolves exact catalog items and ordered canonical images from the active snapshot' do
    tempfile = Tempfile.new(['catalog-images', '.sqlite3'])
    path = tempfile.path
    tempfile.close
    build_catalog(path)
    snapshot = instance_double(IkasCatalogSnapshot, sqlite_exists?: true, sqlite_path: path)

    result = described_class.new(account: account, snapshot: snapshot).resolve(item_ids: %w[variant:blue variant:red])

    expect(result.pluck(:item_id)).to eq(%w[variant:blue variant:red])
    expect(result.first).to include(
      display_name: 'Blue Screen',
      price: include(amount: 599.0, currency: 'TRY'),
      link: include(url: 'https://store.example/blue')
    )
    expect(result.last[:images]).to eq([
                                         { url: 'https://cdn.myikas.com/red-main.webp', scope: 'variant' },
                                         { url: 'https://cdn.myikas.com/red-side.webp', scope: 'variant' }
                                       ])
  ensure
    FileUtils.rm_f(path) if path
  end

  def build_catalog(path)
    db = SQLite3::Database.new(path)
    create_tables(db)
    insert_catalog_rows(db)
  ensure
    db&.close
  end

  def create_tables(db)
    db.execute_batch(<<~SQL.squish)
      CREATE TABLE catalog_items (
        item_id TEXT PRIMARY KEY,
        display_name TEXT,
        price_amount REAL,
        compare_at_price_amount REAL,
        currency TEXT,
        product_url TEXT,
        product_url_source TEXT,
        product_slug TEXT,
        storefront_domain TEXT
      );
      CREATE TABLE catalog_item_images (
        item_id TEXT,
        canonical_url TEXT,
        image_scope TEXT,
        position INTEGER
      );
    SQL
  end

  def insert_catalog_rows(db)
    db.execute_batch(<<~SQL.squish)
      INSERT INTO catalog_items VALUES
        ('variant:red', 'Red Screen', 499, NULL, 'TRY', 'https://store.example/red', 'ikas_slug', 'red', 'store.example'),
        ('variant:blue', 'Blue Screen', 599, NULL, 'TRY', 'https://store.example/blue', 'ikas_slug', 'blue', 'store.example');
      INSERT INTO catalog_item_images VALUES
        ('variant:red', 'https://cdn.myikas.com/red-side.webp', 'variant', 2),
        ('variant:red', 'https://cdn.myikas.com/red-main.webp', 'variant', 1),
        ('variant:blue', 'https://cdn.myikas.com/blue-main.webp', 'variant', 1);
    SQL
  end
end
