class CreateAiAgentEvaluationGenerations < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_agent_evaluation_generations do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :ai_agent, null: false, foreign_key: { on_delete: :cascade }
      t.references :initiated_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :status, null: false, default: 0
      t.integer :requested_count, null: false
      t.integer :created_count, null: false, default: 0
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end

    add_index :ai_agent_evaluation_generations,
              :ai_agent_id,
              unique: true,
              where: 'status IN (0, 1)',
              name: 'index_ai_evaluation_generations_on_active_agent'
  end
end
