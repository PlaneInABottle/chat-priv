class CreateAiKnowledgeSources < ActiveRecord::Migration[7.1]
  def change
    create_sources
    create_assignments
  end

  private

  def create_sources
    create_table :ai_knowledge_sources do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :source_type, null: false, default: 'manual'
      t.text :content, null: false

      t.timestamps
    end

    add_index :ai_knowledge_sources, [:account_id, :name]
    add_check_constraint :ai_knowledge_sources, "source_type = 'manual'", name: 'ai_knowledge_sources_type_check'
    add_check_constraint :ai_knowledge_sources, 'char_length(name) BETWEEN 1 AND 120', name: 'ai_knowledge_sources_name_length_check'
    add_check_constraint :ai_knowledge_sources,
                         'char_length(content) BETWEEN 1 AND 100000',
                         name: 'ai_knowledge_sources_content_length_check'
  end

  def create_assignments
    create_table :ai_knowledge_source_assignments do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :ai_knowledge_source, null: false, foreign_key: { on_delete: :cascade }
      t.string :assistant_type, null: false
      t.bigint :assistant_id, null: false

      t.timestamps
    end

    add_index :ai_knowledge_source_assignments,
              [:assistant_type, :assistant_id, :ai_knowledge_source_id],
              unique: true,
              name: 'index_ai_knowledge_assignments_on_assistant_and_source'
    add_index :ai_knowledge_source_assignments,
              [:account_id, :assistant_type, :assistant_id],
              name: 'index_ai_knowledge_assignments_on_account_and_assistant'
    add_check_constraint :ai_knowledge_source_assignments,
                         "assistant_type IN ('AiAgent', 'VoiceAgent')",
                         name: 'ai_knowledge_assignments_assistant_type_check'
  end
end
