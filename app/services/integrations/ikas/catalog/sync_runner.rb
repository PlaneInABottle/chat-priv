# frozen_string_literal: true

require Rails.root.join('lib/integrations/ikas/catalog')

class Integrations::Ikas::Catalog::SyncRunner
  ERROR_MESSAGE_LIMIT = 2000

  def initialize(snapshot:, hook:)
    @snapshot = snapshot
    @hook = hook
    @store = Integrations::Ikas::Catalog::SnapshotStore.new(snapshot: snapshot)
  end

  def call
    mark_syncing!
    store.prepare!

    manifest = raw_sync_manifest
    build_result = build_catalog(manifest)

    mark_completed!(manifest, build_result)
    store.remove_raw_sync!(manifest)
    store.cleanup_old_completed!
    snapshot
  rescue StandardError => e
    mark_failed!(e)
    raise
  end

  private

  attr_reader :snapshot, :hook, :store

  def mark_syncing!
    snapshot.update!(status: :syncing, started_at: Time.current, completed_at: nil, error_message: nil)
  end

  def mark_completed!(manifest, build_result)
    snapshot.update!(
      status: :completed,
      sqlite_path: store.sqlite_path.to_s,
      counts: counts_for(manifest, build_result),
      metadata: metadata_for(manifest, build_result),
      completed_at: Time.current,
      error_message: nil
    )
  end

  def mark_failed!(error)
    snapshot.update!(
      status: :failed,
      completed_at: Time.current,
      error_message: error.message.to_s.first(ERROR_MESSAGE_LIMIT)
    )
  end

  def raw_sync_manifest
    Integrations::Ikas::Catalog::RawSync.new(
      client: client,
      output_root: store.raw_output_root
    ).perform
  end

  def build_catalog(manifest)
    Integrations::Ikas::Catalog::SqliteBuilder.new(
      snapshot_dir: manifest.fetch('run_dir'),
      sqlite_path: store.sqlite_path
    ).build
  end

  def client
    @client ||= Integrations::Ikas::Catalog::Client.new(
      store_url: hook.reference_id,
      client_id: hook.settings['client_id'],
      client_secret: hook.access_token,
      graphql_url: ENV.fetch('IKAS_API_URL', Integrations::Ikas::Catalog::DEFAULT_GRAPHQL_URL)
    )
  end

  def counts_for(manifest, build_result)
    raw_counts = manifest.fetch('counts', {})
    stats = build_result.fetch('stats', {})

    {
      'products' => raw_counts['products'].to_i,
      'categories' => raw_counts['categories'].to_i,
      'variant_types' => raw_counts['variant_types'].to_i,
      'product_attributes' => raw_counts['product_attributes'].to_i,
      'product_option_sets' => raw_counts['product_option_sets'].to_i,
      'catalog_groups' => stats['catalog_groups'].to_i,
      'catalog_items' => stats['catalog_items'].to_i,
      'catalog_facts' => stats['catalog_facts'].to_i
    }
  end

  def metadata_for(manifest, build_result)
    {
      'engine' => 'ikas_catalog_sqlite_v1',
      'raw_run_id' => manifest['run_id'],
      'raw_started_at' => manifest['started_at'],
      'raw_completed_at' => manifest['completed_at'],
      'sqlite_path' => build_result['sqlite_path'],
      'api_url' => ENV.fetch('IKAS_API_URL', Integrations::Ikas::Catalog::DEFAULT_GRAPHQL_URL)
    }
  end
end
