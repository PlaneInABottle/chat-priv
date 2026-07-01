# frozen_string_literal: true

require Rails.root.join('lib/integrations/ikas/catalog')

class Integrations::Ikas::Catalog::SnapshotStore
  KEEP_COMPLETED_SNAPSHOTS = 3

  def initialize(snapshot:)
    @snapshot = snapshot
  end

  def run_dir
    Rails.root.join(
      'storage',
      'ikas_catalogs',
      'accounts',
      snapshot.account_id.to_s,
      'hooks',
      snapshot.integrations_hook_id.to_s,
      'runs',
      snapshot.id.to_s
    )
  end

  def raw_output_root
    run_dir.join('raw_sync')
  end

  def sqlite_path
    run_dir.join('catalog.sqlite3')
  end

  def prepare!
    FileUtils.mkdir_p(run_dir)
  end

  def remove_raw_sync!(manifest)
    return if ENV['IKAS_CATALOG_KEEP_RAW'].present?

    raw_run_dir = manifest&.[]('run_dir')
    FileUtils.rm_rf(raw_run_dir) if raw_run_dir.to_s.start_with?(run_dir.to_s)
    FileUtils.rm_rf(raw_output_root) if raw_output_root.exist?
  end

  def cleanup_old_completed!
    old_snapshots = snapshot.integrations_hook
                            .ikas_catalog_snapshots
                            .completed
                            .where.not(id: snapshot.id)
                            .order(completed_at: :desc, id: :desc)
                            .offset(KEEP_COMPLETED_SNAPSHOTS - 1)
    old_snapshots.each do |old_snapshot|
      self.class.remove_artifact_for(old_snapshot)
      old_snapshot.destroy!
    end
  end

  def self.remove_artifact_for(snapshot)
    return if snapshot.sqlite_path.blank?

    path = Pathname.new(snapshot.sqlite_path)
    return unless path.to_s.start_with?(Rails.root.join('storage/ikas_catalogs').to_s)

    FileUtils.rm_rf(path.dirname)
  end

  private

  attr_reader :snapshot
end
