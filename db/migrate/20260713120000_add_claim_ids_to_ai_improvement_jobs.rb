class AddClaimIdsToAiImprovementJobs < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_evaluation_generations, :claim_id, :string
    add_column :ai_agent_evaluation_runs, :claim_id, :string
    add_column :ai_agent_learning_suggestions, :claim_id, :string
  end
end
