class Api::V1::Accounts::AiAgentToolExecutionsController < Api::V1::Accounts::BaseController
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100

  before_action :current_account
  before_action :set_ai_agent
  before_action :authorize_ai_agent

  def index
    @tool_executions = filtered_tool_executions.order(created_at: :desc).limit(result_limit)
    @tool_executions_count = @tool_executions.count
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def authorize_ai_agent
    authorize @ai_agent, :show?
  end

  def result_limit
    return DEFAULT_LIMIT if params[:limit].blank?

    params[:limit].to_i.clamp(1, MAX_LIMIT)
  end

  def filtered_tool_executions
    executions = @ai_agent.tool_executions.where(account_id: Current.account.id)
    executions = executions.where(tool_key: params[:tool_key]) if params[:tool_key].present?
    filter_by_mode(filter_by_status(executions))
  end

  def filter_by_status(executions)
    return executions unless params[:status].present? && AiAgentToolExecution.statuses.key?(params[:status])

    executions.where(status: params[:status])
  end

  def filter_by_mode(executions)
    return executions unless params[:mode].present? && AiAgentToolExecution.modes.key?(params[:mode])

    executions.where(mode: params[:mode])
  end
end
