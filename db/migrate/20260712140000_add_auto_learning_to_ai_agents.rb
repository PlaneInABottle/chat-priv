class AddAutoLearningToAiAgents < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_agents, :auto_learning_enabled, :boolean, default: false, null: false
  end
end
