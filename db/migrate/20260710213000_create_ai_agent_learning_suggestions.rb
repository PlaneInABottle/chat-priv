class CreateAiAgentLearningSuggestions < ActiveRecord::Migration[7.1]
  def change
    create_learning_suggestions
    add_learning_suggestion_indexes
  end

  private

  def create_learning_suggestions
    create_table :ai_agent_learning_suggestions do |t|
      add_source_references(t)
      add_review_references(t)
      add_content_fields(t)
      t.timestamps
    end
  end

  def add_source_references(table)
    table.references :account, null: false, foreign_key: { on_delete: :cascade }
    table.references :ai_agent, null: false, foreign_key: { on_delete: :cascade }
    table.references :conversation, null: true, foreign_key: { on_delete: :nullify }
    table.references :source_message, null: true, foreign_key: { to_table: :messages, on_delete: :nullify }
  end

  def add_review_references(table)
    table.references :submitted_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
    table.references :reviewed_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }
    table.datetime :reviewed_at
    table.datetime :applied_at
  end

  def add_content_fields(table)
    table.integer :status, null: false, default: 0
    table.string :target_section
    table.text :customer_message, null: false
    table.text :human_answer, null: false
    table.text :suggested_instruction
    table.text :reason
    table.text :error_message
  end

  def add_learning_suggestion_indexes
    add_index :ai_agent_learning_suggestions,
              [:ai_agent_id, :source_message_id],
              unique: true,
              where: 'source_message_id IS NOT NULL',
              name: 'index_ai_learning_suggestions_on_agent_and_message'
    add_index :ai_agent_learning_suggestions,
              [:ai_agent_id, :status, :created_at],
              name: 'index_ai_learning_suggestions_on_agent_status_created'
  end
end
