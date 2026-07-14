class CreateAiAgentWebsiteImports < ActiveRecord::Migration[7.1]
  def change
    create_website_imports_table
    add_active_import_index
  end

  private

  def create_website_imports_table
    create_table :ai_agent_website_imports do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :ai_agent, null: false, foreign_key: { on_delete: :cascade }
      t.references :requested_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :website_url, null: false
      t.integer :status, null: false, default: 0
      t.integer :stage, null: false, default: 0
      t.jsonb :source_urls, null: false, default: []
      t.jsonb :proposed_sections, null: false, default: {}
      t.string :base_draft_fingerprint, null: false
      t.string :error_code
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at
      t.datetime :applied_at
      t.timestamps
    end
  end

  def add_active_import_index
    add_index :ai_agent_website_imports,
              :ai_agent_id,
              unique: true,
              where: 'status IN (0, 1)',
              name: 'index_ai_website_imports_on_active_agent'
  end
end
