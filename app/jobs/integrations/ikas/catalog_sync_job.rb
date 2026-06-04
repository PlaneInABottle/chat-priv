# frozen_string_literal: true

class Integrations::Ikas::CatalogSyncJob < ApplicationJob
  queue_as :low

  STALE_SYNC_AFTER = 30.minutes

  def perform(hook_id)
    hook = Integrations::Hook.find_by(id: hook_id)
    return unless syncable_hook?(hook)

    mark_stale_syncs!(hook)
    return if active_sync?(hook)

    snapshot = hook.ikas_catalog_snapshots.create!(
      account: hook.account,
      store_host: hook.reference_id,
      status: :pending
    )

    Integrations::Ikas::Catalog::SyncRunner.new(snapshot: snapshot, hook: hook).call
  rescue StandardError => e
    Rails.logger.error("[Integrations::Ikas::CatalogSyncJob] #{e.class}: #{e.message}")
  end

  private

  def syncable_hook?(hook)
    return false unless hook&.app_id == Integrations::Ikas::ConnectionStatus::IKAS_APP_ID
    return false unless Chatwoot.encryption_configured?
    return false unless hook.enabled?
    return false unless hook.account.feature_enabled?('ikas_integration')

    valid_credentials?(hook)
  end

  def valid_credentials?(hook)
    hook.reference_id.present? && hook.access_token.present? && hook.settings['client_id'].present?
  rescue ActiveRecord::Encryption::Errors::Decryption
    false
  end

  def active_sync?(hook)
    hook.ikas_catalog_snapshots
        .syncing
        .exists?(['started_at >= ?', STALE_SYNC_AFTER.ago])
  end

  def mark_stale_syncs!(hook)
    hook.ikas_catalog_snapshots
        .syncing
        .where('started_at < ? OR started_at IS NULL', STALE_SYNC_AFTER.ago)
        .find_each do |snapshot|
          snapshot.update!(
            status: :failed,
            completed_at: Time.current,
            error_message: 'Catalog sync timed out.'
          )
        end
  end
end
