class AllowVoiceTestCallsWithoutConversations < ActiveRecord::Migration[7.1]
  def change
    change_column_null :calls, :contact_id, true
    change_column_null :calls, :conversation_id, true
    change_column_null :call_transcript_segments, :conversation_id, true
  end
end
