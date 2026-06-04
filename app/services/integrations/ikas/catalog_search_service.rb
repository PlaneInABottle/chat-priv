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
    result = query_engine(snapshot).query(query_text, limit: clamped_limit)
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
                         .latest_completed
                         .first
  end

  def query_engine(snapshot)
    Integrations::Ikas::Catalog::QueryEngine.new(sqlite_path: snapshot.sqlite_path)
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
