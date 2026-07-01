# == Schema Information
#
# Table name: voice_numbers
#
#  id                           :bigint           not null, primary key
#  last_error                   :text
#  phone_number                 :string           not null
#  settings                     :jsonb            not null
#  status                       :string           default("draft"), not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  account_id                   :bigint           not null
#  livekit_dispatch_rule_id     :string
#  livekit_inbound_trunk_id     :string
#  voice_inbox_setting_id       :bigint           not null
#  voice_provider_connection_id :bigint           not null
#
# Indexes
#
#  idx_voice_numbers_provider_connection            (voice_provider_connection_id)
#  idx_voice_numbers_voice_inbox_setting            (voice_inbox_setting_id)
#  index_voice_numbers_on_account_id                (account_id)
#  index_voice_numbers_on_livekit_dispatch_rule_id  (livekit_dispatch_rule_id)
#  index_voice_numbers_on_livekit_inbound_trunk_id  (livekit_inbound_trunk_id)
#  index_voice_numbers_on_phone_number              (phone_number) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (voice_inbox_setting_id => voice_inbox_settings.id)
#  fk_rails_...  (voice_provider_connection_id => voice_provider_connections.id)
#
class VoiceNumber < ApplicationRecord
  STATUSES = %w[draft active failed disabled].freeze

  belongs_to :account
  belongs_to :voice_provider_connection
  belongs_to :voice_inbox_setting
  has_one :inbox, through: :voice_inbox_setting
  has_one :voice_agent, through: :voice_inbox_setting

  validates :phone_number, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validate :associations_belong_to_account

  before_validation :normalize_phone_number

  scope :active, -> { where(status: 'active') }
  scope :for_dialed_number, ->(number) { number.present? ? where(phone_number: normalize_number(number)) : none }

  def self.normalize_number(value)
    value.to_s.strip.gsub(/[[:space:]\-()]/, '')
  end

  private

  def normalize_phone_number
    self.phone_number = self.class.normalize_number(phone_number)
  end

  def associations_belong_to_account
    if voice_provider_connection && voice_provider_connection.account_id != account_id
      errors.add(:voice_provider_connection_id, 'must belong to account')
    end
    return unless voice_inbox_setting && voice_inbox_setting.account_id != account_id

    errors.add(:voice_inbox_setting_id, 'must belong to account')
  end
end
