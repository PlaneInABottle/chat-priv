# frozen_string_literal: true

# == Schema Information
#
# Table name: ikas_catalog_snapshots
#
#  id                   :bigint           not null, primary key
#  completed_at         :datetime
#  counts               :jsonb            not null
#  error_message        :text
#  metadata             :jsonb            not null
#  sqlite_path          :text
#  started_at           :datetime
#  status               :integer          default("pending"), not null
#  store_host           :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  integrations_hook_id :bigint           not null
#
# Indexes
#
#  idx_ikas_snapshots_on_account_hook_created_at         (account_id,integrations_hook_id,created_at)
#  idx_ikas_snapshots_on_account_status_completed_at     (account_id,status,completed_at)
#  idx_ikas_snapshots_on_hook_status                     (integrations_hook_id,status)
#  index_ikas_catalog_snapshots_on_account_id            (account_id)
#  index_ikas_catalog_snapshots_on_integrations_hook_id  (integrations_hook_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (integrations_hook_id => integrations_hooks.id) ON DELETE => cascade
#
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
  scope :storefront_catalog, -> { where("metadata ->> 'engine' = ?", 'ikas_catalog_sqlite_v2') }

  def sqlite_exists?
    sqlite_path.present? && File.exist?(sqlite_path)
  end
end
