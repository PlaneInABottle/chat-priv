class CreateVoiceRecordings < ActiveRecord::Migration[7.1]
  def change
    create_table :voice_recordings do |t|
      t.references :account, null: false, foreign_key: true, index: true
      t.references :call, null: false, foreign_key: true, index: true
      t.string :egress_id
      t.string :status, null: false, default: 'starting'
      t.string :storage_provider, null: false, default: 's3_compatible'
      t.string :bucket
      t.string :object_key
      t.string :content_type
      t.integer :duration_seconds
      t.datetime :started_at
      t.datetime :completed_at
      t.text :error_message
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :voice_recordings, :egress_id, unique: true, where: 'egress_id IS NOT NULL'
    add_index :voice_recordings, [:account_id, :status]
    add_index :voice_recordings, [:account_id, :created_at]
  end
end
