class CreateIkasCatalogSnapshots < ActiveRecord::Migration[7.1]
  def change
    create_table :ikas_catalog_snapshots do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }
      t.references :integrations_hook, null: false, foreign_key: { to_table: :integrations_hooks, on_delete: :cascade }
      t.string :store_host, null: false
      t.integer :status, null: false, default: 0
      t.text :sqlite_path
      t.jsonb :counts, null: false, default: {}
      t.jsonb :metadata, null: false, default: {}
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message

      t.timestamps
    end

    add_index :ikas_catalog_snapshots, [:account_id, :integrations_hook_id, :created_at], name: 'idx_ikas_snapshots_on_account_hook_created_at'
    add_index :ikas_catalog_snapshots, [:account_id, :status, :completed_at], name: 'idx_ikas_snapshots_on_account_status_completed_at'
    add_index :ikas_catalog_snapshots, [:integrations_hook_id, :status], name: 'idx_ikas_snapshots_on_hook_status'
  end
end
