json.array! @ai_agents do |ai_agent|
  json.id ai_agent.id
  json.name ai_agent.name
  json.prompt ai_agent.prompt
  json.enabled ai_agent.enabled
  json.enabled_tool_keys AiAgents::Config.new(ai_agent.config).enabled_tool_keys
  json.created_at ai_agent.created_at
  json.updated_at ai_agent.updated_at
  json.lifecycle_status ai_agent.lifecycle_status
  json.published_at ai_agent.published_at
  json.published_revision ai_agent.published_revision
  json.current_release AssistantReleases::Serializer.new(ai_agent.current_release).payload if ai_agent.current_release
  json.draft_changes ai_agent.draft_changes?
  json.last_tested_at ai_agent.last_tested_at
  json.readiness ai_agent.readiness

  if ai_agent.agent_bot.present?
    json.agent_bot do
      json.id ai_agent.agent_bot.id
      json.name ai_agent.agent_bot.name
      json.bot_type ai_agent.agent_bot.bot_type
      json.inbox_ids ai_agent.agent_bot.inboxes.pluck(:id)
    end
  end

  json.account_ai_agent_enabled ai_agent.account.ai_agent_enabled?
end
