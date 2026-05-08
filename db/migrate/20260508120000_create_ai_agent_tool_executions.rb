class CreateAiAgentToolExecutions < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_tool_executions do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :ai_agent, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :message, foreign_key: { on_delete: :nullify }
      t.string :tool_key, null: false
      t.string :tool_name
      t.integer :mode, null: false
      t.integer :status, null: false
      t.string :error_code
      t.text :error_message
      t.string :tool_call_id
      t.jsonb :arguments, default: {}, null: false
      t.jsonb :result, default: {}, null: false
      t.boolean :terminal, default: false, null: false
      t.integer :duration_ms
      t.timestamps
    end

    add_index :ai_agent_tool_executions, [:account_id, :created_at]
    add_index :ai_agent_tool_executions, [:ai_agent_id, :created_at]
    add_index :ai_agent_tool_executions, :tool_key
  end
end
