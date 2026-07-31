class RemoveModeFromAiAgentWebsiteImports < ActiveRecord::Migration[7.2]
  def up
    remove_column :ai_agent_website_imports, :mode, :integer if column_exists?(:ai_agent_website_imports, :mode)
  end

  def down
    return if column_exists?(:ai_agent_website_imports, :mode)

    add_column :ai_agent_website_imports, :mode, :integer, default: 0, null: false
  end
end
