class Api::V1::Accounts::AiAgentEvaluationCasesController < Api::V1::Accounts::BaseController
  MAX_CASES = 20

  before_action :current_account
  before_action :check_authorization
  before_action :ensure_ai_agent_enabled
  before_action :set_ai_agent
  before_action :set_evaluation_case, only: [:update, :destroy]

  def index
    @evaluation_cases = @ai_agent.evaluation_cases.order(:position, :created_at)
  end

  def create
    @ai_agent.with_lock do
      next render_case_limit_error if @ai_agent.evaluation_cases.count >= MAX_CASES

      @evaluation_case = @ai_agent.evaluation_cases.build(evaluation_case_params)
      @evaluation_case.account = Current.account
      @evaluation_case.position = next_position

      if @evaluation_case.save
        render :show
      else
        render json: { errors: @evaluation_case.errors }, status: :unprocessable_entity
      end
    end
  end

  def update
    if @evaluation_case.update(evaluation_case_params)
      render :show
    else
      render json: { errors: @evaluation_case.errors }, status: :unprocessable_entity
    end
  end

  def destroy
    @evaluation_case.destroy!
    head :no_content
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def set_evaluation_case
    @evaluation_case = @ai_agent.evaluation_cases.find(params[:id])
  end

  def evaluation_case_params
    params.permit(:name, :customer_message, :success_criteria)
  end

  def next_position
    @ai_agent.evaluation_cases.maximum(:position).to_i + 1
  end

  def render_case_limit_error
    render json: { error: "An assistant can have up to #{MAX_CASES} evaluation scenarios." }, status: :unprocessable_entity
  end
end
