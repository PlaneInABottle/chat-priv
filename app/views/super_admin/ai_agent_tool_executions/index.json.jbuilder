json.meta do
  json.count @tool_executions_count
  json.current_page 1
  json.filters @tool_execution_query.filters
end

json.payload do
  json.array! @tool_executions do |execution|
    json.extract! controller.send(:serialized_execution, execution), :id, :account_id, :account_name, :ai_agent_id, :ai_agent_name,
                  :conversation_id, :conversation_display_id, :conversation_url, :message_id, :tool_key, :tool_name, :mode, :status,
                  :error_code, :error_message, :tool_call_id, :arguments, :result, :terminal, :duration_ms, :created_at
  end
end
