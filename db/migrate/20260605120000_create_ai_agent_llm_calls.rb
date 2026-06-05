class CreateAiAgentLlmCalls < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_llm_calls do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :ai_agent, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :message, foreign_key: { on_delete: :nullify }
      t.string :model
      t.string :step, null: false
      t.integer :mode, null: false
      t.integer :status, null: false
      t.jsonb :request_messages, default: [], null: false
      t.jsonb :request_tool_names, default: [], null: false
      t.jsonb :response, default: {}, null: false
      t.jsonb :usage, default: {}, null: false
      t.string :finish_reason
      t.string :error_code
      t.text :error_message
      t.integer :duration_ms
      t.timestamps
    end

    add_index :ai_agent_llm_calls, [:account_id, :created_at]
    add_index :ai_agent_llm_calls, [:ai_agent_id, :created_at]
    add_index :ai_agent_llm_calls, [:conversation_id, :created_at]
    add_index :ai_agent_llm_calls, :status
  end
end
