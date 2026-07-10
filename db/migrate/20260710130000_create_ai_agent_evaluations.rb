class CreateAiAgentEvaluations < ActiveRecord::Migration[7.1]
  def change
    create_evaluation_cases
    create_evaluation_runs
    create_evaluation_results
  end

  private

  def create_evaluation_cases
    create_table :ai_agent_evaluation_cases do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :ai_agent, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.text :customer_message, null: false
      t.text :success_criteria, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :ai_agent_evaluation_cases, [:ai_agent_id, :position]
  end

  def create_evaluation_runs
    create_table :ai_agent_evaluation_runs do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :ai_agent, null: false, foreign_key: { on_delete: :cascade }
      t.integer :status, null: false, default: 0
      t.text :prompt_snapshot, null: false
      t.jsonb :config_snapshot, null: false, default: {}
      t.string :draft_fingerprint, null: false
      t.integer :total_count, null: false, default: 0
      t.integer :passed_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.timestamps
    end
    create_evaluation_run_indexes
  end

  def create_evaluation_run_indexes
    add_index :ai_agent_evaluation_runs, [:ai_agent_id, :created_at]
    add_index :ai_agent_evaluation_runs,
              :ai_agent_id,
              unique: true,
              where: 'status IN (0, 1)',
              name: 'index_ai_evaluation_runs_on_active_agent'
  end

  def create_evaluation_results
    create_table :ai_agent_evaluation_results do |t|
      t.references :ai_agent_evaluation_run,
                   null: false,
                   foreign_key: { on_delete: :cascade },
                   index: { name: 'index_ai_evaluation_results_on_run_id' }
      t.references :ai_agent_evaluation_case,
                   null: true,
                   foreign_key: { on_delete: :nullify },
                   index: { name: 'index_ai_evaluation_results_on_case_id' }
      t.integer :status, null: false, default: 0
      t.string :case_name, null: false
      t.text :customer_message, null: false
      t.text :success_criteria, null: false
      t.text :assistant_response
      t.boolean :passed, null: false, default: false
      t.text :reason
      t.jsonb :tool_events, null: false, default: []
      t.timestamps
    end
  end
end
