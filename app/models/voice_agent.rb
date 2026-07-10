# == Schema Information
#
# Table name: voice_agents
#
#  id             :bigint           not null, primary key
#  architecture   :string           default("realtime"), not null
#  config         :jsonb            not null
#  enabled        :boolean          default(FALSE), not null
#  greeting       :text
#  language       :string           default("tr"), not null
#  last_tested_at :datetime
#  model          :string
#  name           :string           default("Voice Assistant"), not null
#  prompt         :text             default(""), not null
#  provider       :string           default("gemini"), not null
#  published_at   :datetime
#  tools_config   :jsonb            not null
#  voice          :string           default("Charon"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#
# Indexes
#
#  index_voice_agents_on_account_id                 (account_id)
#  index_voice_agents_on_account_id_and_created_at  (account_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class VoiceAgent < ApplicationRecord
  ARCHITECTURES = %w[realtime pipeline].freeze
  PROVIDERS = %w[gemini openai].freeze

  belongs_to :account
  has_many :voice_inbox_settings, dependent: :nullify

  scope :enabled, -> { where(enabled: true) }

  validates :name, presence: true
  validates :architecture, presence: true, inclusion: { in: ARCHITECTURES }
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :language, presence: true
  validates :voice, presence: true
  validates :greeting, length: { maximum: 20_000 }
  validates :prompt, length: { maximum: 50_000 }
  validate :tools_config_must_be_valid

  before_validation :set_defaults

  def lifecycle_status
    return 'active' if enabled?
    return 'paused' if published_at.present?

    'draft'
  end

  def readiness
    VoiceAgents::Readiness.new(self).payload
  end

  def publish!
    raise ActiveRecord::RecordInvalid, self unless readiness[:can_publish]

    update!(enabled: true, published_at: published_at || Time.current)
  end

  def pause!
    update!(enabled: false)
  end

  def mark_test_succeeded!
    update!(last_tested_at: Time.current)
  end

  private

  def set_defaults
    self.tools_config = {} unless tools_config.is_a?(Hash)
    self.config = {} unless config.is_a?(Hash)
  end

  def tools_config_must_be_valid
    parsed_config = VoiceAgents::Config.new(tools_config)
    return if parsed_config.valid?

    parsed_config.errors.each { |message| errors.add(:tools_config, message) }
  end
end
