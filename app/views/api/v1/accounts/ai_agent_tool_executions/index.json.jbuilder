json.meta do
  json.count @tool_executions_count
  json.current_page 1
  json.filters @tool_execution_query.filters
end

json.payload do
  json.array! @tool_executions do |execution|
    json.id execution.id
    json.account_id execution.account_id
    json.account_name execution.account&.name
    json.ai_agent_id execution.ai_agent_id
    json.ai_agent_name execution.ai_agent&.name
    json.conversation_id execution.conversation_id
    json.conversation_display_id execution.conversation&.display_id
    json.conversation_url execution.conversation ? "/app/accounts/#{execution.account_id}/conversations/#{execution.conversation.display_id}" : nil
    json.message_id execution.message_id
    json.tool_key execution.tool_key
    json.tool_name AiAgents::ToolRegistry.find(execution.tool_key)&.name || execution.tool_name || execution.tool_key.to_s.humanize
    json.mode execution.mode
    json.status execution.status
    json.error_code execution.error_code
    json.error_message execution.error_message
    json.tool_call_id execution.tool_call_id
    json.arguments execution.arguments
    json.result execution.result
    json.terminal execution.terminal
    json.duration_ms execution.duration_ms
    json.created_at execution.created_at
  end
end
