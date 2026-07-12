class AddSyncMetadataToAiKnowledgeSources < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :ai_knowledge_sources, name: 'ai_knowledge_sources_type_check'
    remove_check_constraint :ai_knowledge_sources, name: 'ai_knowledge_sources_content_length_check'

    add_column :ai_knowledge_sources, :website_url, :string
    add_column :ai_knowledge_sources, :sync_status, :integer, default: 0, null: false
    add_column :ai_knowledge_sources, :source_urls, :jsonb, default: [], null: false
    add_column :ai_knowledge_sources, :last_sync_started_at, :datetime
    add_column :ai_knowledge_sources, :last_synced_at, :datetime
    add_column :ai_knowledge_sources, :sync_error, :text

    add_index :ai_knowledge_sources, [:account_id, :source_type]
    add_check_constraint :ai_knowledge_sources,
                         "source_type IN ('manual', 'website')",
                         name: 'ai_knowledge_sources_type_check'
    add_check_constraint :ai_knowledge_sources,
                         "(source_type = 'manual' AND char_length(content) BETWEEN 1 AND 100000) OR " \
                         "(source_type = 'website' AND char_length(content) BETWEEN 0 AND 100000)",
                         name: 'ai_knowledge_sources_content_length_check'
    add_check_constraint :ai_knowledge_sources,
                         "source_type != 'website' OR website_url IS NOT NULL",
                         name: 'ai_knowledge_sources_website_url_check'
  end

  def down
    remove_check_constraint :ai_knowledge_sources, name: 'ai_knowledge_sources_website_url_check'
    remove_check_constraint :ai_knowledge_sources, name: 'ai_knowledge_sources_content_length_check'
    remove_check_constraint :ai_knowledge_sources, name: 'ai_knowledge_sources_type_check'
    remove_index :ai_knowledge_sources, [:account_id, :source_type]

    remove_columns :ai_knowledge_sources,
                   :website_url,
                   :sync_status,
                   :source_urls,
                   :last_sync_started_at,
                   :last_synced_at,
                   :sync_error

    add_check_constraint :ai_knowledge_sources, "source_type = 'manual'", name: 'ai_knowledge_sources_type_check'
    add_check_constraint :ai_knowledge_sources,
                         'char_length(content) BETWEEN 1 AND 100000',
                         name: 'ai_knowledge_sources_content_length_check'
  end
end
