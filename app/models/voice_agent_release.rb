# frozen_string_literal: true

# == Schema Information
#
# Table name: voice_agent_releases
#
#  id             :bigint           not null, primary key
#  fingerprint    :string           not null
#  revision       :integer          not null
#  snapshot       :jsonb            not null
#  source         :string           default("publish"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint           not null
#  created_by_id  :bigint
#  voice_agent_id :bigint           not null
#
# Indexes
#
#  index_voice_agent_releases_on_account_id                   (account_id)
#  index_voice_agent_releases_on_account_id_and_created_at    (account_id,created_at)
#  index_voice_agent_releases_on_created_by_id                (created_by_id)
#  index_voice_agent_releases_on_voice_agent_id               (voice_agent_id)
#  index_voice_agent_releases_on_voice_agent_id_and_revision  (voice_agent_id,revision) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (voice_agent_id => voice_agents.id) ON DELETE => cascade
#
class VoiceAgentRelease < ApplicationRecord
  SOURCES = %w[publish rollback migration].freeze

  belongs_to :account
  belongs_to :voice_agent
  belongs_to :created_by, class_name: 'User', optional: true

  validates :revision, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :voice_agent_id }
  validates :source, inclusion: { in: SOURCES }
  validates :fingerprint, presence: true
  validate :records_belong_to_account

  def value(key)
    snapshot.to_h[key.to_s]
  end

  private

  def records_belong_to_account
    return if account.blank? || voice_agent.blank? || voice_agent.account_id == account_id

    errors.add(:account, 'must own the Voice agent')
  end
end
