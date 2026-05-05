class AddNameToAiAgentsAndRemoveUniqueness < ActiveRecord::Migration[7.1]
  def up
    add_column :ai_agents, :name, :string, null: false, default: 'AI Asistan'
    remove_index :ai_agents, :account_id
    add_index :ai_agents, :account_id
  end

  def down
    remove_index :ai_agents, :account_id
    add_index :ai_agents, :account_id, unique: true
    remove_column :ai_agents, :name
  end
end
