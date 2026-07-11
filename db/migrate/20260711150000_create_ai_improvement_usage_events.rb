class CreateAiImprovementUsageEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_improvement_usage_events do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :ai_agent, foreign_key: { on_delete: :nullify }
      t.references :voice_agent, foreign_key: { on_delete: :nullify }
      t.references :call, foreign_key: { on_delete: :nullify }
      t.references :initiated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :operation, null: false
      t.string :unit_type, null: false
      t.bigint :units, null: false, default: 0
      t.integer :credits, null: false, default: 1
      t.integer :status, null: false, default: 0
      t.datetime :period_start_at, null: false
      t.datetime :period_end_at, null: false
      t.string :idempotency_key, null: false
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end

    add_usage_indexes
  end

  private

  def add_usage_indexes
    add_index :ai_improvement_usage_events, [:account_id, :period_start_at, :idempotency_key],
              unique: true, name: 'idx_ai_improvement_usage_on_idempotency'
    add_index :ai_improvement_usage_events, [:account_id, :period_start_at, :status],
              name: 'idx_ai_improvement_usage_on_account_period_status'
    add_index :ai_improvement_usage_events, [:account_id, :operation, :created_at],
              name: 'idx_ai_improvement_usage_on_account_operation'
  end
end
