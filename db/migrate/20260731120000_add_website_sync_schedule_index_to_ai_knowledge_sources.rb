class AddWebsiteSyncScheduleIndexToAiKnowledgeSources < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :ai_knowledge_sources,
              [:source_type, :sync_status, :last_synced_at],
              name: 'idx_ai_knowledge_sources_on_website_sync_schedule',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
