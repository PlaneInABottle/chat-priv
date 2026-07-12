# == Schema Information
#
# Table name: ai_agent_evaluation_generations
#
#  id              :bigint           not null, primary key
#  completed_at    :datetime
#  created_count   :integer          default(0), not null
#  error_message   :text
#  requested_count :integer          not null
#  started_at      :datetime
#  status          :integer          default("pending"), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  ai_agent_id     :bigint           not null
#  initiated_by_id :bigint
#
# Indexes
#
#  index_ai_agent_evaluation_generations_on_account_id       (account_id)
#  index_ai_agent_evaluation_generations_on_ai_agent_id      (ai_agent_id)
#  index_ai_agent_evaluation_generations_on_initiated_by_id  (initiated_by_id)
#  index_ai_evaluation_generations_on_active_agent           (ai_agent_id) UNIQUE WHERE (status = ANY (ARRAY[0, 1]))
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_agent_id => ai_agents.id) ON DELETE => cascade
#  fk_rails_...  (initiated_by_id => users.id) ON DELETE => nullify
#
class AiAgentEvaluationGeneration < ApplicationRecord
  MAX_REQUESTED_COUNT = 5

  enum status: { pending: 0, running: 1, completed: 2, failed: 3 }

  belongs_to :account
  belongs_to :ai_agent
  belongs_to :initiated_by, class_name: 'User', optional: true

  validates :requested_count, numericality: { only_integer: true, in: 1..MAX_REQUESTED_COUNT }
  validates :created_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :records_belong_to_account

  private

  def records_belong_to_account
    return if account.blank?
    return if ai_agent&.account_id == account_id && (initiated_by.blank? || account.users.exists?(initiated_by.id))

    errors.add(:account, 'must own all linked records')
  end
end
