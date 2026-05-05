class CreateAiAgentTestConversations < ActiveRecord::Migration[7.0]
  def change
    create_table :ai_agent_test_conversations do |t|
      t.bigint :account_id, null: false
      t.bigint :ai_agent_id, null: false
      t.string :title
      t.jsonb :messages, default: [], null: false
      t.datetime :last_message_at
      t.timestamps
    end

    add_index :ai_agent_test_conversations, :account_id
    add_index :ai_agent_test_conversations, :ai_agent_id
    add_index :ai_agent_test_conversations, :last_message_at
  end
end
