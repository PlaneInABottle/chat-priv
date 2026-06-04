class Api::V1::Accounts::AiAgentToolExecutionsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :set_ai_agent
  before_action :authorize_ai_agent
  before_action :ensure_ai_agent_enabled

  def index
    @tool_execution_query = AiAgents::ToolExecutionQuery.new(scope: tool_executions_scope, params: params)
    @tool_executions = @tool_execution_query.results.includes(:account, :ai_agent, :conversation)
    @tool_executions_count = @tool_executions.count
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def authorize_ai_agent
    authorize @ai_agent, :show?
  end

  def tool_executions_scope
    @ai_agent.tool_executions.where(account_id: Current.account.id)
  end
end
