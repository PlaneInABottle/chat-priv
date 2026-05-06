json.id @ai_agent.id
json.account_id @ai_agent.account_id
json.name @ai_agent.name
json.prompt @ai_agent.prompt
json.enabled @ai_agent.enabled
json.config @ai_agent.config
json.model @ai_agent.account.ai_agent_model
json.conversation_limit @ai_agent.account.ai_agent_conversation_limit
json.created_at @ai_agent.created_at
json.updated_at @ai_agent.updated_at

if @ai_agent.agent_bot.present?
  json.agent_bot do
    json.id @ai_agent.agent_bot.id
    json.name @ai_agent.agent_bot.name
    json.bot_type @ai_agent.agent_bot.bot_type
    json.thumbnail @ai_agent.agent_bot.avatar_url
    json.inbox_ids @ai_agent.agent_bot.inboxes.pluck(:id)
  end
end

json.available_inboxes @available_inboxes do |inbox|
  owner_bot = inbox.agent_bot
  owned_by_current_ai_agent = owner_bot&.id == @ai_agent.agent_bot_id
  conflicting = owner_bot.present? && !owned_by_current_ai_agent
  owner_name = owner_bot&.ai_agent&.name.presence || owner_bot&.name.presence

  json.id inbox.id
  json.name inbox.name
  json.avatar_url inbox.avatar_url
  json.channel_type inbox.channel_type
  json.available owner_bot.blank?
  json.owned_by_current_ai_agent owned_by_current_ai_agent
  json.conflicting conflicting
  json.owner_name owner_name
end
