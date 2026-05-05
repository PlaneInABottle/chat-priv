json.array! @ai_agents do |ai_agent|
  json.id ai_agent.id
  json.name ai_agent.name
  json.prompt ai_agent.prompt
  json.enabled ai_agent.enabled
  json.created_at ai_agent.created_at
  json.updated_at ai_agent.updated_at

  if ai_agent.agent_bot.present?
    json.agent_bot do
      json.id ai_agent.agent_bot.id
      json.name ai_agent.agent_bot.name
      json.bot_type ai_agent.agent_bot.bot_type
      json.inbox_ids ai_agent.agent_bot.inboxes.pluck(:id)
    end
  end

  json.conversation_limit ai_agent.account.ai_agent_conversation_limit
  json.ai_agent_model ai_agent.account.ai_agent_model
end
