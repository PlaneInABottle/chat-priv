class CreateVoiceProviderConnectionsAndNumbers < ActiveRecord::Migration[7.1]
  def change
    create_voice_provider_connections
    create_voice_numbers
  end

  private

  def create_voice_provider_connections
    create_table :voice_provider_connections do |t|
      t.references :account, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :name, null: false
      t.string :status, null: false, default: 'draft'
      t.jsonb :settings, null: false, default: {}
      t.text :last_error

      t.timestamps
    end

    add_index :voice_provider_connections,
              [:account_id, :provider, :name],
              unique: true,
              name: 'idx_voice_provider_connections_account_provider_name'
  end

  def create_voice_numbers
    create_table :voice_numbers do |t|
      t.references :account, null: false, foreign_key: true
      t.references :voice_provider_connection, null: false, foreign_key: true, index: { name: 'idx_voice_numbers_provider_connection' }
      t.references :voice_inbox_setting, null: false, foreign_key: true, index: { name: 'idx_voice_numbers_voice_inbox_setting' }
      t.string :phone_number, null: false
      t.string :status, null: false, default: 'draft'
      t.string :livekit_inbound_trunk_id
      t.string :livekit_dispatch_rule_id
      t.jsonb :settings, null: false, default: {}
      t.text :last_error

      t.timestamps
    end

    add_index :voice_numbers, :phone_number, unique: true
    add_index :voice_numbers, :livekit_inbound_trunk_id
    add_index :voice_numbers, :livekit_dispatch_rule_id
  end
end
