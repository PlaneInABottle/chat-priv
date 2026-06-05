# frozen_string_literal: true

require 'fileutils'
require 'sqlite3'

module IkasCatalogMvp
  class SqliteBuilder
    GROUP_COLUMNS = %w[
      group_id product_id display_name primary_category_id product_url product_slug product_url_source
      storefront_id storefront_domain storefront_sales_channel_id item_count in_stock_count min_price_amount
      max_price_amount currency search_text raw_json
    ].freeze
    ITEM_COLUMNS = %w[
      item_id group_id product_id variant_id entity_type display_name display_subtitle primary_category_id product_url
      product_slug product_url_source storefront_id storefront_domain storefront_sales_channel_id price_amount currency
      stock_quantity in_stock sellable image_id search_text search_text_folded raw_json
    ].freeze
    FACT_COLUMNS = %w[
      item_id type key value_text value_folded numeric_value numeric_value_2 unit source confidence raw
    ].freeze

    def initialize(snapshot_dir:, sqlite_path: nil)
      @snapshot_dir = Pathname.new(snapshot_dir)
      @sqlite_path = Pathname.new(sqlite_path || @snapshot_dir.join('catalog.sqlite3'))
    end

    def build
      FileUtils.mkdir_p(sqlite_path.dirname)
      FileUtils.rm_f(sqlite_path)
      validate_storefront_scope!
      db.execute_batch(schema_sql)
      insert_raw_rows
      insert_normalized_rows
      { 'sqlite_path' => sqlite_path.to_s, 'stats' => stats, 'storefronts' => link_builder.eligible_storefronts }
    ensure
      @db&.close
    end

    private

    attr_reader :snapshot_dir, :sqlite_path

    def raw_dir
      snapshot_dir.join('raw')
    end

    def db
      @db ||= SQLite3::Database.new(sqlite_path.to_s).tap { |database| database.results_as_hash = true }
    end

    def schema_sql
      <<~SQL
        CREATE TABLE raw_categories (id TEXT PRIMARY KEY, parent_id TEXT, name TEXT, raw_json TEXT NOT NULL);
        CREATE TABLE raw_variant_types (id TEXT PRIMARY KEY, name TEXT, raw_json TEXT NOT NULL);
        CREATE TABLE raw_product_attributes (id TEXT PRIMARY KEY, name TEXT, type TEXT, raw_json TEXT NOT NULL);
        CREATE TABLE raw_product_option_sets (id TEXT PRIMARY KEY, name TEXT, raw_json TEXT NOT NULL);
        CREATE TABLE raw_storefronts (
          id TEXT PRIMARY KEY,
          name TEXT,
          type TEXT,
          status TEXT,
          sales_channel_id TEXT,
          domain TEXT,
          raw_json TEXT NOT NULL
        );
        CREATE TABLE raw_products (id TEXT PRIMARY KEY, name TEXT, raw_json TEXT NOT NULL);
        CREATE TABLE catalog_groups (
          group_id TEXT PRIMARY KEY,
          product_id TEXT NOT NULL,
          display_name TEXT NOT NULL,
          primary_category_id TEXT,
          product_url TEXT,
          product_slug TEXT,
          product_url_source TEXT,
          storefront_id TEXT,
          storefront_domain TEXT,
          storefront_sales_channel_id TEXT,
          item_count INTEGER NOT NULL,
          in_stock_count INTEGER NOT NULL,
          min_price_amount REAL,
          max_price_amount REAL,
          currency TEXT,
          search_text TEXT,
          raw_json TEXT NOT NULL
        );
        CREATE TABLE catalog_items (
          item_id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          product_id TEXT NOT NULL,
          variant_id TEXT,
          entity_type TEXT NOT NULL,
          display_name TEXT NOT NULL,
          display_subtitle TEXT,
          primary_category_id TEXT,
          product_url TEXT,
          product_slug TEXT,
          product_url_source TEXT,
          storefront_id TEXT,
          storefront_domain TEXT,
          storefront_sales_channel_id TEXT,
          price_amount REAL,
          currency TEXT,
          stock_quantity REAL,
          in_stock INTEGER NOT NULL,
          sellable INTEGER NOT NULL,
          image_id TEXT,
          search_text TEXT,
          search_text_folded TEXT,
          raw_json TEXT NOT NULL
        );
        CREATE TABLE catalog_item_categories (item_id TEXT NOT NULL, category_id TEXT NOT NULL);
        CREATE TABLE catalog_group_categories (group_id TEXT NOT NULL, category_id TEXT NOT NULL);
        CREATE TABLE catalog_facets (
          item_id TEXT NOT NULL,
          key TEXT NOT NULL,
          key_folded TEXT NOT NULL,
          value TEXT NOT NULL,
          value_folded TEXT NOT NULL,
          source TEXT NOT NULL
        );
        CREATE TABLE catalog_facts (
          item_id TEXT NOT NULL,
          type TEXT NOT NULL,
          key TEXT,
          value_text TEXT,
          value_folded TEXT,
          numeric_value REAL,
          numeric_value_2 REAL,
          unit TEXT,
          source TEXT NOT NULL,
          confidence TEXT NOT NULL,
          raw TEXT
        );
        CREATE INDEX index_catalog_items_on_search ON catalog_items(search_text_folded);
        CREATE INDEX index_catalog_items_on_group ON catalog_items(group_id);
        CREATE INDEX index_catalog_item_categories_on_category ON catalog_item_categories(category_id, item_id);
        CREATE INDEX index_catalog_group_categories_on_category ON catalog_group_categories(category_id, group_id);
        CREATE INDEX index_catalog_facets_on_key_value ON catalog_facets(key_folded, value_folded, item_id);
        CREATE INDEX index_catalog_facts_on_type ON catalog_facts(type, item_id);
        CREATE INDEX index_catalog_facts_on_numeric ON catalog_facts(type, numeric_value, numeric_value_2, unit, item_id);
      SQL
    end

    def insert_raw_rows
      insert_raw_categories
      insert_raw_variant_types
      insert_raw_product_attributes
      insert_raw_product_option_sets
      insert_raw_storefronts
      insert_raw_products
    end

    def insert_raw_categories
      each_jsonl('categories') do |row|
        db.execute(
          'INSERT INTO raw_categories (id, parent_id, name, raw_json) VALUES (?, ?, ?, ?)',
          [row['id'], row['parentId'], row['name'], Text.json(row)]
        )
      end
    end

    def insert_raw_variant_types
      each_jsonl('variant_types') do |row|
        db.execute('INSERT INTO raw_variant_types (id, name, raw_json) VALUES (?, ?, ?)', [row['id'], row['name'], Text.json(row)])
      end
    end

    def insert_raw_product_attributes
      each_jsonl('product_attributes') do |row|
        db.execute(
          'INSERT INTO raw_product_attributes (id, name, type, raw_json) VALUES (?, ?, ?, ?)',
          [row['id'], row['name'], row['type'], Text.json(row)]
        )
      end
    end

    def insert_raw_product_option_sets
      each_jsonl('product_option_sets') do |row|
        db.execute('INSERT INTO raw_product_option_sets (id, name, raw_json) VALUES (?, ?, ?)', [row['id'], row['name'], Text.json(row)])
      end
    end

    def insert_raw_storefronts
      each_jsonl('storefronts') do |row|
        link_storefront = link_builder.eligible_storefronts.find { |storefront| storefront.fetch('id') == row['id'] }
        db.execute(
          'INSERT INTO raw_storefronts (id, name, type, status, sales_channel_id, domain, raw_json) VALUES (?, ?, ?, ?, ?, ?, ?)',
          [row['id'], row['name'], row['type'], row['status'], row['salesChannelId'], link_storefront&.fetch('domain', nil), Text.json(row)]
        )
      end
    end

    def insert_raw_products
      each_jsonl('products') do |row|
        next unless link_builder.product_visible?(row)

        db.execute('INSERT INTO raw_products (id, name, raw_json) VALUES (?, ?, ?)', [row['id'], row['name'], Text.json(row)])
      end
    end

    def insert_normalized_rows
      normalizer = Normalizer.new(
        categories: load_jsonl('categories'),
        variant_types: load_jsonl('variant_types'),
        product_attributes: load_jsonl('product_attributes'),
        product_option_sets: load_jsonl('product_option_sets'),
        storefronts: load_jsonl('storefronts')
      )

      each_jsonl('products') do |product|
        next unless normalizer.product_visible?(product)

        normalized = normalizer.normalize_product(product)
        insert_group(normalized.fetch(:group))
        normalized.fetch(:items).each { |item| insert_item(item) }
        normalized.fetch(:categories).each { |row| insert_item_category(row) }
        normalized.fetch(:group_categories).each { |row| insert_group_category(row) }
        normalized.fetch(:facets).each { |row| insert_facet(row) }
        normalized.fetch(:facts).each { |row| insert_fact(row) }
      end
    end

    def insert_group(row)
      insert_hash_row('catalog_groups', GROUP_COLUMNS, row)
    end

    def insert_item(row)
      insert_hash_row('catalog_items', ITEM_COLUMNS, row)
    end

    def insert_item_category(row)
      db.execute('INSERT INTO catalog_item_categories (item_id, category_id) VALUES (?, ?)', row.values_at('item_id', 'category_id'))
    end

    def insert_group_category(row)
      db.execute('INSERT INTO catalog_group_categories (group_id, category_id) VALUES (?, ?)', row.values_at('group_id', 'category_id'))
    end

    def insert_facet(row)
      db.execute(
        'INSERT INTO catalog_facets (item_id, key, key_folded, value, value_folded, source) VALUES (?, ?, ?, ?, ?, ?)',
        [row['item_id'], row['key'], Text.fold(row['key']), row['value'], Text.fold(row['value']), row['source']]
      )
    end

    def insert_fact(row)
      insert_hash_row('catalog_facts', FACT_COLUMNS, row)
    end

    def insert_hash_row(table, columns, row)
      db.execute(
        "INSERT INTO #{table} (#{columns.join(', ')}) VALUES (#{Array.new(columns.length, '?').join(', ')})",
        columns.map { |column| row[column] }
      )
    end

    def stats
      %w[raw_products raw_storefronts catalog_groups catalog_items catalog_facets catalog_facts].to_h do |table|
        [table, db.get_first_value("SELECT COUNT(*) FROM #{table}")]
      end.merge(
        'products_with_links' => db.get_first_value('SELECT COUNT(DISTINCT product_id) FROM catalog_groups WHERE product_url IS NOT NULL').to_i
      )
    end

    def load_jsonl(name)
      path = raw_dir.join("#{name}.jsonl")
      return [] unless path.exist?

      path.readlines(chomp: true).reject(&:empty?).map { |line| JSON.parse(line) }
    end

    def each_jsonl(name)
      load_jsonl(name).each { |row| yield row }
    end

    def validate_storefront_scope!
      return if link_builder.eligible_storefronts.any?

      raise Error, 'No READY public Ikas storefront found for catalog sync.'
    end

    def link_builder
      @link_builder ||= ProductLinkBuilder.new(storefronts: load_jsonl('storefronts'))
    end
  end
end
