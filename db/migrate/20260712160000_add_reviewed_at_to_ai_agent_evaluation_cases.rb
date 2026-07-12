class AddReviewedAtToAiAgentEvaluationCases < ActiveRecord::Migration[7.1]
  def up
    add_column :ai_agent_evaluation_cases, :reviewed_at, :datetime
    execute <<~SQL.squish
      UPDATE ai_agent_evaluation_cases
      SET reviewed_at = created_at
    SQL
  end

  def down
    remove_column :ai_agent_evaluation_cases, :reviewed_at
  end
end
