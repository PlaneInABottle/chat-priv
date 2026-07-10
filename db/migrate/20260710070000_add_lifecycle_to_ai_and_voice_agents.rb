class AddLifecycleToAiAndVoiceAgents < ActiveRecord::Migration[7.1]
  def up
    add_column :ai_agents, :published_at, :datetime
    add_column :ai_agents, :last_tested_at, :datetime
    add_column :voice_agents, :published_at, :datetime
    add_column :voice_agents, :last_tested_at, :datetime

    execute <<~SQL.squish
      UPDATE ai_agents
      SET published_at = updated_at
      WHERE enabled = TRUE
    SQL
    execute <<~SQL.squish
      UPDATE voice_agents
      SET published_at = updated_at
      WHERE enabled = TRUE
    SQL
  end

  def down
    remove_column :voice_agents, :last_tested_at
    remove_column :voice_agents, :published_at
    remove_column :ai_agents, :last_tested_at
    remove_column :ai_agents, :published_at
  end
end
