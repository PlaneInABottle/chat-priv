class CreateVoiceInboxSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :voice_inbox_settings do |t|
      t.references :account, null: false, foreign_key: true
      t.references :inbox, null: false, foreign_key: true
      t.references :ai_agent, foreign_key: true
      t.references :fallback_team, foreign_key: { to_table: :teams }
      t.string :status, null: false, default: 'test_only'
      t.string :livekit_room_prefix
      t.text :greeting
      t.text :instructions
      t.boolean :recording_enabled, null: false, default: false
      t.text :last_error
      t.jsonb :settings, null: false, default: {}

      t.timestamps
    end

    add_index :voice_inbox_settings, [:account_id, :inbox_id], unique: true
  end
end
