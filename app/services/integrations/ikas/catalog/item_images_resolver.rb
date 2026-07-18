# frozen_string_literal: true

require Rails.root.join('lib/integrations/ikas/catalog')

class Integrations::Ikas::Catalog::ItemImagesResolver
  def initialize(account:, snapshot: nil)
    @account = account
    @snapshot = snapshot
  end

  def resolve(item_ids:)
    ids = Array(item_ids).map(&:to_s).uniq
    return [] if ids.empty? || !snapshot&.sqlite_exists?

    with_db do |db|
      return [] unless image_table_exists?(db)

      resolve_items(db, ids)
    end
  rescue SQLite3::Exception => e
    Rails.logger.error("[IkasCatalogImages] #{e.class}: #{e.message}")
    []
  end

  private

  attr_reader :account

  def snapshot
    @snapshot ||= begin
      status = Integrations::Ikas::ConnectionStatus.new(account: account).payload
      hook = status[:hook] if status[:state] == 'connected'
      hook&.ikas_catalog_snapshots&.storefront_catalog&.latest_completed&.first
    end
  end

  def with_db
    db = SQLite3::Database.new(snapshot.sqlite_path)
    db.results_as_hash = true
    yield db
  ensure
    db&.close
  end

  def image_table_exists?(db)
    db.get_first_value("SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'catalog_item_images' LIMIT 1") == 1
  end

  def resolve_items(db, ids)
    items = catalog_items(db, ids).index_by { |item| item.fetch(:item_id) }
    ids.filter_map do |item_id|
      item = items[item_id]
      item&.merge(images: images_for(db, item_id))
    end
  end

  def catalog_items(db, ids)
    placeholders = Array.new(ids.length, '?').join(', ')
    db.execute(<<~SQL.squish, ids).map do |row|
      SELECT item_id, display_name, price_amount, compare_at_price_amount, currency,
             product_url, product_url_source, product_slug, storefront_domain
      FROM catalog_items
      WHERE item_id IN (#{placeholders})
    SQL
      {
        item_id: row.fetch('item_id'),
        display_name: row.fetch('display_name'),
        price: price_payload(row),
        link: link_payload(row)
      }
    end
  end

  def images_for(db, item_id)
    db.execute(<<~SQL.squish, [item_id]).map do |row|
      SELECT canonical_url, image_scope
      FROM catalog_item_images
      WHERE item_id = ?
      ORDER BY position ASC
    SQL
      { url: row.fetch('canonical_url'), scope: row.fetch('image_scope') }
    end
  end

  def price_payload(row)
    {
      amount: row['price_amount'],
      compare_at_amount: row['compare_at_price_amount'],
      currency: row['currency'],
      final_total_known: !row['price_amount'].nil?
    }.compact
  end

  def link_payload(row)
    return if row['product_url'].blank?

    {
      url: row['product_url'],
      source: row['product_url_source'],
      slug: row['product_slug'],
      storefront_domain: row['storefront_domain']
    }.compact
  end
end
