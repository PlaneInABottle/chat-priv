tool_config = AiAgents::Config.new(@ai_agent.config)
ikas_summary = Integrations::Ikas::ConnectionStatus.new(account: @ai_agent.account).payload
tool_availability = AiAgents::ToolAvailability.new(account: @ai_agent.account)
available_tools = tool_availability.available_definitions(AiAgents::ToolRegistry.available_definitions)
tools_summary = tool_config.tools_summary
tools_summary[AiAgents::Config::ENABLED_KEY] = tool_availability.filter_enabled_keys(
  tools_summary[AiAgents::Config::ENABLED_KEY],
  AiAgents::ToolRegistry.available_definitions
)
config_payload = @ai_agent.config.to_h.deep_stringify_keys
instruction_source = config_payload['instructions']
config_payload['instructions'] = if instruction_source.present?
                                   AiAgents::InstructionDocument.new(instruction_source).normalized
                                 else
                                   AiAgents::InstructionDocument.from_legacy(@ai_agent.prompt)
                                 end

json.id @ai_agent.id
json.account_id @ai_agent.account_id
json.name @ai_agent.name
json.prompt @ai_agent.prompt
json.enabled @ai_agent.enabled
json.config config_payload
json.tools_config tools_summary
json.available_tools available_tools do |tool|
  json.key tool.key
  json.name tool.name
  json.description tool.description
  json.mode_support tool.mode_support
  json.terminal tool.terminal
end
json.ikas_integration do
  json.feature_enabled @ai_agent.account.feature_enabled?('ikas_integration')
  json.state ikas_summary[:state]
  json.can_connect ikas_summary[:can_connect]
  if ikas_summary[:hook].present?
    latest_snapshot = ikas_summary[:hook].ikas_catalog_snapshots.order(created_at: :desc, id: :desc).first
    completed_snapshot = ikas_summary[:hook].ikas_catalog_snapshots.storefront_catalog.latest_completed.first
    json.catalog_sync do
      json.status latest_snapshot&.status || 'not_synced'
      json.last_synced_at completed_snapshot&.completed_at&.iso8601
      json.products_count completed_snapshot&.counts&.[]('products').to_i
      json.catalog_items_count completed_snapshot&.counts&.[]('catalog_items').to_i
      json.error_message latest_snapshot&.failed? ? latest_snapshot.error_message : nil
    end
  end
end
json.account_ai_agent_enabled @ai_agent.account.ai_agent_enabled?
json.created_at @ai_agent.created_at
json.updated_at @ai_agent.updated_at
json.lifecycle_status @ai_agent.lifecycle_status
json.published_at @ai_agent.published_at
json.last_tested_at @ai_agent.last_tested_at
json.readiness @ai_agent.readiness

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
