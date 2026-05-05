json.array! @test_conversations do |conversation|
  json.id conversation.id
  json.title conversation.title
  json.messages_count conversation.messages_count
  json.last_message_preview conversation.last_message_preview
  json.last_message_at conversation.last_message_at
  json.created_at conversation.created_at
  json.updated_at conversation.updated_at
end
