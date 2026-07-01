class CreateAiAgentUsageEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_usage_events do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :ai_agent, null: false, foreign_key: { on_delete: :cascade }
      t.references :contact, foreign_key: { on_delete: :nullify }
      t.references :conversation, foreign_key: { on_delete: :nullify }
      t.references :message, foreign_key: { on_delete: :nullify }
      t.integer :period, null: false, default: 0
      t.datetime :period_start_at, null: false
      t.datetime :period_end_at, null: false
      t.datetime :window_started_at, null: false
      t.datetime :window_ends_at, null: false
      t.integer :status, null: false, default: 0
      t.timestamps
    end

    add_index :ai_agent_usage_events, [:account_id, :period, :period_start_at, :status], name: 'idx_ai_agent_usage_events_on_account_period_status'
    add_index :ai_agent_usage_events, [:account_id, :contact_id, :window_ends_at], name: 'idx_ai_agent_usage_events_on_account_contact_window'
    add_index :ai_agent_usage_events, [:conversation_id, :created_at], name: 'idx_ai_agent_usage_events_on_conversation_created_at'
  end
end
