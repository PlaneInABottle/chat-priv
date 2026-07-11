# frozen_string_literal: true

# == Schema Information
#
# Table name: ai_agent_releases
#
#  id            :bigint           not null, primary key
#  fingerprint   :string           not null
#  revision      :integer          not null
#  snapshot      :jsonb            not null
#  source        :string           default("publish"), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  ai_agent_id   :bigint           not null
#  created_by_id :bigint
#
# Indexes
#
#  index_ai_agent_releases_on_account_id                 (account_id)
#  index_ai_agent_releases_on_account_id_and_created_at  (account_id,created_at)
#  index_ai_agent_releases_on_ai_agent_id                (ai_agent_id)
#  index_ai_agent_releases_on_ai_agent_id_and_revision   (ai_agent_id,revision) UNIQUE
#  index_ai_agent_releases_on_created_by_id              (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_agent_id => ai_agents.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class AiAgentRelease < ApplicationRecord
  SOURCES = %w[publish rollback migration].freeze

  belongs_to :account
  belongs_to :ai_agent
  belongs_to :created_by, class_name: 'User', optional: true

  validates :revision, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :ai_agent_id }
  validates :source, inclusion: { in: SOURCES }
  validates :fingerprint, presence: true
  validate :records_belong_to_account

  def prompt
    snapshot.to_h['prompt'].to_s
  end

  def config
    snapshot.to_h['config'].to_h
  end

  private

  def records_belong_to_account
    return if account.blank? || ai_agent.blank? || ai_agent.account_id == account_id

    errors.add(:account, 'must own the AI agent')
  end
end
