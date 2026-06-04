# frozen_string_literal: true

class IkasCatalogSnapshot < ApplicationRecord
  belongs_to :account
  belongs_to :integrations_hook, class_name: 'Integrations::Hook', inverse_of: :ikas_catalog_snapshots

  enum status: {
    pending: 0,
    syncing: 1,
    completed: 2,
    failed: 3
  }

  validates :store_host, presence: true
  validates :status, presence: true

  scope :latest_completed, -> { completed.order(completed_at: :desc, id: :desc) }
  scope :for_hook, ->(hook) { where(integrations_hook: hook) }

  def sqlite_exists?
    sqlite_path.present? && File.exist?(sqlite_path)
  end
end
