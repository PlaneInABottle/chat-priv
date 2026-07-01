# == Schema Information
#
# Table name: voice_provider_connections
#
#  id         :bigint           not null, primary key
#  last_error :text
#  name       :string           not null
#  provider   :string           not null
#  settings   :jsonb            not null
#  status     :string           default("draft"), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  idx_voice_provider_connections_account_provider_name  (account_id,provider,name) UNIQUE
#  index_voice_provider_connections_on_account_id        (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class VoiceProviderConnection < ApplicationRecord
  PROVIDERS = %w[test_sip manual_sip netgsm livekit_number].freeze
  STATUSES = %w[draft active failed disabled].freeze

  belongs_to :account
  has_many :voice_numbers, dependent: :destroy

  validates :name, presence: true
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :name, uniqueness: { scope: [:account_id, :provider] }
end
