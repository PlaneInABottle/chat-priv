# frozen_string_literal: true

require Rails.root.join('lib/integrations/ikas/catalog')

class Integrations::Ikas::CatalogSearchService
  DEFAULT_LIMIT = 8
  MAX_LIMIT = 20

  def initialize(account:, query_text:, limit: DEFAULT_LIMIT)
    @account = account
    @query_text = query_text.to_s
    @limit = limit.to_i
  end

  def call
    error = validation_error
    return error if error

    search_result(latest_snapshot).deep_symbolize_keys
  rescue IkasCatalogMvp::Error => e
    return retry_after_fts_repair if fts_missing_error?(e)

    Rails.logger.error("[Integrations::Ikas::CatalogSearchService] #{e.class}: #{e.message}")
    error_payload('catalog_query_failed', 'Ikas catalog search failed.')
  rescue StandardError => e
    Rails.logger.error("[Integrations::Ikas::CatalogSearchService] #{e.class}: #{e.message}")
    error_payload('catalog_query_failed', 'Ikas catalog search failed.')
  end

  private

  attr_reader :account, :query_text, :limit

  def validation_error
    return error_payload('invalid_query', 'Catalog query cannot be blank.') if query_text.blank?
    return error_payload('ikas_feature_disabled', 'Ikas integration is not enabled for this account.') unless ikas_feature_enabled?
    return error_payload('ikas_not_connected', 'Ikas integration is not connected.') unless connected_hook
    return error_payload('catalog_not_ready', 'Ikas catalog has not completed its first sync yet.') unless latest_snapshot
    return error_payload('catalog_missing', 'Ikas catalog file is missing. Sync the catalog again.') unless latest_snapshot.sqlite_exists?

    nil
  end

  def search_result(snapshot)
    engine = query_engine(snapshot)
    result = engine.query(query_text, limit: clamped_limit)
    result.merge(
      'status' => 'ok',
      'catalog' => {
        'store_host' => snapshot.store_host,
        'synced_at' => snapshot.completed_at&.iso8601,
        'snapshot_id' => snapshot.id
      }
    )
  end

  def ikas_feature_enabled?
    account.feature_enabled?('ikas_integration')
  end

  def connected_hook
    @connected_hook ||= begin
      status = Integrations::Ikas::ConnectionStatus.new(account: account).payload
      status[:state] == 'connected' ? status[:hook] : nil
    end
  end

  def latest_snapshot
    @latest_snapshot ||= IkasCatalogSnapshot
                         .where(account: account, integrations_hook: connected_hook)
                         .storefront_catalog
                         .latest_completed
                         .first
  end

  def query_engine(snapshot)
    Integrations::Ikas::Catalog::QueryEngine.new(sqlite_path: snapshot.sqlite_path)
  end

  def retry_after_fts_repair
    raise 'Ikas catalog FTS repair failed' if @fts_repair_attempted

    @fts_repair_attempted = true
    repair_fts_index!(latest_snapshot)
    search_result(latest_snapshot).deep_symbolize_keys
  rescue StandardError => e
    Rails.logger.error("[Integrations::Ikas::CatalogSearchService] #{e.class}: #{e.message}")
    error_payload('catalog_query_failed', 'Ikas catalog search failed.')
  end

  def fts_missing_error?(error)
    error.message.to_s.include?('Ikas catalog FTS index is missing')
  end

  def repair_fts_index!(snapshot)
    db = SQLite3::Database.new(snapshot.sqlite_path)
    db.results_as_hash = true
    db.execute_batch(<<~SQL)
      DROP TABLE IF EXISTS catalog_items_fts;
      CREATE VIRTUAL TABLE catalog_items_fts USING fts5(
        item_id UNINDEXED,
        display_name,
        search_text,
        tokenize = 'unicode61'
      );
    SQL
    db.transaction
    db.execute('SELECT item_id, display_name, search_text_folded FROM catalog_items') do |row|
      db.execute(
        'INSERT INTO catalog_items_fts (item_id, display_name, search_text) VALUES (?, ?, ?)',
        [row.fetch('item_id'), Integrations::Ikas::Catalog::Text.fold(row.fetch('display_name')), row.fetch('search_text_folded')]
      )
    end
    db.commit
    snapshot.update!(metadata: (snapshot.metadata || {}).merge('fts_repaired_at' => Time.current.iso8601))
  ensure
    db&.rollback if db&.transaction_active?
    db&.close
  end

  def clamped_limit
    (limit.positive? ? limit : DEFAULT_LIMIT).clamp(1, MAX_LIMIT)
  end

  def error_payload(code, message)
    {
      status: 'error',
      error_code: code,
      error_message: message,
      warnings: []
    }
  end
end
