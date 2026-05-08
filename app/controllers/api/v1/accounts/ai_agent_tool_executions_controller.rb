class Api::V1::Accounts::AiAgentToolExecutionsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :set_ai_agent
  before_action :authorize_ai_agent

  def index
    @tool_executions = filtered_tool_executions.order(created_at: :desc)
    @tool_executions_count = @tool_executions.count
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def authorize_ai_agent
    authorize @ai_agent, :show?
  end

  def filtered_tool_executions
    executions = @ai_agent.tool_executions.where(account_id: Current.account.id)
    executions = executions.where(status: params[:status]) if params[:status].present? && AiAgentToolExecution.statuses.key?(params[:status])
    executions = executions.where(mode: params[:mode]) if params[:mode].present? && AiAgentToolExecution.modes.key?(params[:mode])
    executions = executions.where(tool_key: params[:tool_key]) if params[:tool_key].present?
    executions
  end
end
