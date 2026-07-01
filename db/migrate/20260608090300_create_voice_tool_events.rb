class CreateVoiceToolEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :voice_tool_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :call, null: false, foreign_key: true
      t.string :tool, null: false
      t.string :status, null: false, default: 'executed'
      t.jsonb :arguments, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.text :error_message
      t.integer :duration_ms
      t.string :source, null: false, default: 'livekit_agent'
      t.string :external_id

      t.timestamps
    end

    add_index :voice_tool_events, [:call_id, :created_at], name: 'idx_voice_tool_events_on_call_created'
    add_index :voice_tool_events, [:call_id, :external_id],
              unique: true,
              where: "external_id IS NOT NULL",
              name: 'idx_voice_tool_events_on_call_external_id'
    add_index :voice_tool_events, [:account_id, :tool], name: 'idx_voice_tool_events_on_account_tool'
  end
end
