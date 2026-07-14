class AddReviewContextToAiAgentWebsiteImports < ActiveRecord::Migration[7.1]
  def up
    add_column :ai_agent_website_imports, :base_document, :jsonb
    add_column :ai_agent_website_imports, :proposed_knowledge_content, :text
    add_reference :ai_agent_website_imports,
                  :ai_knowledge_source,
                  foreign_key: { on_delete: :nullify },
                  index: true

    remove_column :ai_agent_website_imports, :mode, :integer
  end

  def down
    add_column :ai_agent_website_imports, :mode, :integer, default: 1, null: false
    remove_reference :ai_agent_website_imports, :ai_knowledge_source, foreign_key: true
    remove_columns :ai_agent_website_imports, :base_document, :proposed_knowledge_content
  end
end
