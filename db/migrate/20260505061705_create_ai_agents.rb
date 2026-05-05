class CreateAiAgents < ActiveRecord::Migration[7.1]
  def up
    # Drop dependent tables from prior experiment (no models or code reference them)
    drop_table :ai_agent_runs, if_exists: true
    drop_table :ai_agent_tool_bindings, if_exists: true
    drop_table :ai_agent_versions, if_exists: true
    drop_table :ai_agents, if_exists: true

    create_table :ai_agents do |t|
      t.bigint :account_id, null: false
      t.bigint :agent_bot_id
      t.text :prompt, default: ''
      t.boolean :enabled, default: false, null: false
      t.jsonb :config, default: {}

      t.timestamps
    end

    add_foreign_key :ai_agents, :accounts, on_delete: :cascade
    add_foreign_key :ai_agents, :agent_bots, on_delete: :nullify
    add_index :ai_agents, :account_id, unique: true
    add_index :ai_agents, :agent_bot_id, unique: true
  end

  def down
    drop_table :ai_agents, if_exists: true
  end
end
