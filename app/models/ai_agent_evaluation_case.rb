# == Schema Information
#
# Table name: ai_agent_evaluation_cases
#
#  id               :bigint           not null, primary key
#  customer_message :text             not null
#  name             :string           not null
#  position         :integer          default(0), not null
#  success_criteria :text             not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  ai_agent_id      :bigint           not null
#
# Indexes
#
#  index_ai_agent_evaluation_cases_on_account_id                (account_id)
#  index_ai_agent_evaluation_cases_on_ai_agent_id               (ai_agent_id)
#  index_ai_agent_evaluation_cases_on_ai_agent_id_and_position  (ai_agent_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_agent_id => ai_agents.id) ON DELETE => cascade
#
class AiAgentEvaluationCase < ApplicationRecord
  belongs_to :account
  belongs_to :ai_agent
  has_many :evaluation_results,
           class_name: 'AiAgentEvaluationResult',
           dependent: :nullify,
           inverse_of: :evaluation_case

  validates :name, presence: true, length: { maximum: 100 }
  validates :customer_message, presence: true, length: { maximum: 5_000 }
  validates :success_criteria, presence: true, length: { maximum: 5_000 }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :ai_agent_belongs_to_account

  private

  def ai_agent_belongs_to_account
    return if ai_agent.blank? || account.blank? || ai_agent.account_id == account_id

    errors.add(:ai_agent, 'must belong to account')
  end
end
