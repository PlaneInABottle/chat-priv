class CreateCallTranscriptSegments < ActiveRecord::Migration[7.1]
  def change
    create_table :call_transcript_segments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :call, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.string :source, null: false, default: 'livekit_agent'
      t.text :text, null: false
      t.float :confidence
      t.datetime :started_at
      t.datetime :ended_at
      t.string :external_segment_id
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :call_transcript_segments, [:call_id, :created_at], name: 'idx_call_segments_on_call_created'
    add_index :call_transcript_segments, [:account_id, :conversation_id], name: 'idx_call_segments_on_account_conversation'
    add_index :call_transcript_segments, [:call_id, :external_segment_id],
              unique: true,
              where: "external_segment_id IS NOT NULL",
              name: 'idx_call_segments_on_call_external_id'
  end
end
