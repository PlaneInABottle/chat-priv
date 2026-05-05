class ChangeEnabledNotNullOnAiAgents < ActiveRecord::Migration[7.1]
  def change
    change_column_null :ai_agents, :enabled, false
  end
end
