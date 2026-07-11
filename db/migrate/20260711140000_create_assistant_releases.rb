class CreateAssistantReleases < ActiveRecord::Migration[7.1]
  def change
    create_ai_agent_releases
    create_voice_agent_releases
    add_agent_release_references
    add_runtime_release_references
  end

  private

  def create_ai_agent_releases
    create_table :ai_agent_releases do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :ai_agent, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :revision, null: false
      t.string :source, null: false, default: 'publish'
      t.string :fingerprint, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :ai_agent_releases, [:ai_agent_id, :revision], unique: true
    add_index :ai_agent_releases, [:account_id, :created_at]
  end

  def create_voice_agent_releases
    create_table :voice_agent_releases do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :voice_agent, null: false, foreign_key: { on_delete: :cascade }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.integer :revision, null: false
      t.string :source, null: false, default: 'publish'
      t.string :fingerprint, null: false
      t.jsonb :snapshot, null: false, default: {}
      t.timestamps
    end
    add_index :voice_agent_releases, [:voice_agent_id, :revision], unique: true
    add_index :voice_agent_releases, [:account_id, :created_at]
  end

  def add_agent_release_references
    add_reference :ai_agents, :current_release, foreign_key: { to_table: :ai_agent_releases, on_delete: :nullify }
    add_reference :voice_agents, :current_release, foreign_key: { to_table: :voice_agent_releases, on_delete: :nullify }
    add_column :voice_agents, :last_tested_draft_fingerprint, :string
  end

  def add_runtime_release_references
    add_reference :conversations, :ai_agent_release, foreign_key: { on_delete: :nullify }
    add_reference :calls, :voice_agent_release, foreign_key: { on_delete: :nullify }
  end
end
