class AddKnowledgeSnapshotToAiAgentEvaluationRuns < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agent_evaluation_runs, :knowledge_snapshot, :jsonb, default: [], null: false
  end
end
