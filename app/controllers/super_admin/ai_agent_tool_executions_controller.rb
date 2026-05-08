class SuperAdmin::AiAgentToolExecutionsController < SuperAdmin::ApplicationController
  def index
    @tool_execution_query = AiAgents::ToolExecutionQuery.new(
      scope: tool_executions_scope,
      params: params,
      super_admin: true,
      strict_dates: json_request?
    )
    return render json: { errors: @tool_execution_query.errors }, status: :unprocessable_entity unless @tool_execution_query.valid?

    @tool_executions = @tool_execution_query.results.includes(:account, :ai_agent, :conversation)
    @tool_executions_count = @tool_executions.count

    respond_to do |format|
      format.html { render_html_index }
      format.json
    end
  end

  private

  def render_html_index
    @component_props = {
      initial_payload: serialized_response,
      tool_options: tool_options,
      account_options: account_options
    }
  end

  def tool_executions_scope
    scope = AiAgentToolExecution.left_joins(:account)
    scope = scope.where(account_id: params[:account_id].to_i) if params[:account_id].present?
    scope = scope.where(ai_agent_id: params[:ai_agent_id].to_i) if params[:ai_agent_id].present?
    scope
  end

  def serialized_response
    {
      meta: { count: @tool_executions_count, current_page: 1, filters: @tool_execution_query.filters },
      payload: @tool_executions.map { |execution| serialized_execution(execution) }
    }
  end

  # rubocop:disable Metrics/MethodLength
  def serialized_execution(execution)
    {
      id: execution.id,
      account_id: execution.account_id,
      account_name: execution.account&.name,
      ai_agent_id: execution.ai_agent_id,
      ai_agent_name: execution.ai_agent&.name,
      conversation_id: execution.conversation_id,
      conversation_display_id: execution.conversation&.display_id,
      conversation_url: conversation_url(execution),
      message_id: execution.message_id,
      tool_key: execution.tool_key,
      tool_name: tool_name(execution),
      mode: execution.mode,
      status: execution.status,
      error_code: execution.error_code,
      error_message: execution.error_message,
      tool_call_id: execution.tool_call_id,
      arguments: execution.arguments,
      result: execution.result,
      terminal: execution.terminal,
      duration_ms: execution.duration_ms,
      created_at: execution.created_at
    }
  end
  # rubocop:enable Metrics/MethodLength

  def conversation_url(execution)
    return unless execution.conversation

    "/app/accounts/#{execution.account_id}/conversations/#{execution.conversation.display_id}"
  end

  def tool_name(execution)
    AiAgents::ToolRegistry.find(execution.tool_key)&.name || execution.tool_name || execution.tool_key.to_s.humanize
  end

  def tool_options
    AiAgents::ToolRegistry.available_definitions.map { |tool| { key: tool.key, name: tool.name } }
  end

  def account_options
    Account.order(:name).pluck(:id, :name).map { |id, name| { id: id, name: name } }
  end

  def json_request?
    request.format.json?
  end
end
