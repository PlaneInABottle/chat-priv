# == Schema Information
#
# Table name: ai_agent_evaluation_runs
#
#  id                :bigint           not null, primary key
#  completed_at      :datetime
#  config_snapshot   :jsonb            not null
#  draft_fingerprint :string           not null
#  error_message     :text
#  passed_count      :integer          default(0), not null
#  prompt_snapshot   :text             not null
#  started_at        :datetime
#  status            :integer          default("pending"), not null
#  total_count       :integer          default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  ai_agent_id       :bigint           not null
#  claim_id          :string
#
# Indexes
#
#  index_ai_agent_evaluation_runs_on_account_id                  (account_id)
#  index_ai_agent_evaluation_runs_on_ai_agent_id                 (ai_agent_id)
#  index_ai_agent_evaluation_runs_on_ai_agent_id_and_created_at  (ai_agent_id,created_at)
#  index_ai_evaluation_runs_on_active_agent                      (ai_agent_id) UNIQUE WHERE (status = ANY (ARRAY[0, 1]))
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_agent_id => ai_agents.id) ON DELETE => cascade
#
class AiAgentEvaluationRun < ApplicationRecord
  enum status: { pending: 0, running: 1, completed: 2, failed: 3 }

  belongs_to :account
  belongs_to :ai_agent
  has_many :evaluation_results,
           class_name: 'AiAgentEvaluationResult',
           dependent: :destroy,
           inverse_of: :evaluation_run

  validates :status, :prompt_snapshot, :draft_fingerprint, presence: true
  validates :total_count, :passed_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ai_agent_belongs_to_account

  def current_draft?
    draft_fingerprint == ai_agent.draft_fingerprint
  end

  private

  def ai_agent_belongs_to_account
    return if ai_agent.blank? || account.blank? || ai_agent.account_id == account_id

    errors.add(:ai_agent, 'must belong to account')
  end
end
