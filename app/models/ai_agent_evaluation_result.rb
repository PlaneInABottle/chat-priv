# == Schema Information
#
# Table name: ai_agent_evaluation_results
#
#  id                          :bigint           not null, primary key
#  assistant_response          :text
#  case_name                   :string           not null
#  customer_message            :text             not null
#  passed                      :boolean          default(FALSE), not null
#  reason                      :text
#  status                      :integer          default("pending"), not null
#  success_criteria            :text             not null
#  tool_events                 :jsonb            not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  ai_agent_evaluation_case_id :bigint
#  ai_agent_evaluation_run_id  :bigint           not null
#
# Indexes
#
#  index_ai_evaluation_results_on_case_id  (ai_agent_evaluation_case_id)
#  index_ai_evaluation_results_on_run_id   (ai_agent_evaluation_run_id)
#
# Foreign Keys
#
#  fk_rails_...  (ai_agent_evaluation_case_id => ai_agent_evaluation_cases.id) ON DELETE => nullify
#  fk_rails_...  (ai_agent_evaluation_run_id => ai_agent_evaluation_runs.id) ON DELETE => cascade
#
class AiAgentEvaluationResult < ApplicationRecord
  enum status: { pending: 0, completed: 1, failed: 2 }

  belongs_to :evaluation_run,
             class_name: 'AiAgentEvaluationRun',
             foreign_key: :ai_agent_evaluation_run_id,
             inverse_of: :evaluation_results
  belongs_to :evaluation_case,
             class_name: 'AiAgentEvaluationCase',
             foreign_key: :ai_agent_evaluation_case_id,
             inverse_of: :evaluation_results,
             optional: true

  validates :status, :case_name, :customer_message, :success_criteria, presence: true
  validates :case_name, length: { maximum: 100 }
  validates :customer_message, :success_criteria, length: { maximum: 5_000 }
end
