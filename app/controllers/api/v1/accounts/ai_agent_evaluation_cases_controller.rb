class Api::V1::Accounts::AiAgentEvaluationCasesController < Api::V1::Accounts::BaseController
  MAX_CASES = AiAgentEvaluationCase::MAX_PER_ASSISTANT

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
      @evaluation_case.reviewed_at = Time.current

      if @evaluation_case.save
        render :show
      else
        render json: { errors: @evaluation_case.errors }, status: :unprocessable_entity
      end
    end
  end

  def generate
    expire_stale_generations!
    available_slots = MAX_CASES - @ai_agent.evaluation_cases.count
    return render_case_limit_error unless available_slots.positive?
    return render_generation_running_error if active_generation

    ensure_ai_improvement_credits!(operation: 'evaluation', ai_agent: @ai_agent)
    @evaluation_generation = @ai_agent.evaluation_generations.create!(
      account: Current.account,
      initiated_by: Current.user,
      requested_count: [available_slots, AiAgentEvaluationGeneration::MAX_REQUESTED_COUNT].min
    )
    AiAgents::EvaluationCaseGenerationJob.perform_later(@evaluation_generation)
    render json: generation_payload(@evaluation_generation), status: :accepted
  rescue ActiveRecord::RecordNotUnique
    render_generation_running_error
  rescue AiImprovements::Usage::Exhausted => e
    render_ai_improvement_credits_exhausted(e)
  end

  def generation
    expire_stale_generations!
    latest_generation = @ai_agent.evaluation_generations.order(created_at: :desc).first
    render json: latest_generation ? generation_payload(latest_generation) : {}
  end

  def update
    if @evaluation_case.update(evaluation_case_params.merge(reviewed_at: Time.current))
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

  def active_generation
    @active_generation ||= @ai_agent.evaluation_generations.pending.or(@ai_agent.evaluation_generations.running).first
  end

  def expire_stale_generations!
    @ai_agent.evaluation_generations.pending.where('created_at < ?', AiAgentEvaluationGeneration::CLAIM_TIMEOUT.ago).find_each do |generation|
      generation.update!(
        status: :failed,
        claim_id: nil,
        error_message: AiAgentEvaluationGeneration::USER_FACING_FAILURE,
        completed_at: Time.current
      )
    end
  end

  def generation_payload(generation)
    {
      id: generation.id,
      status: generation.status,
      requested_count: generation.requested_count,
      created_count: generation.created_count,
      error_message: generation.error_message,
      created_at: generation.created_at,
      completed_at: generation.completed_at
    }
  end

  def render_case_limit_error
    render json: { error: "An assistant can have up to #{MAX_CASES} evaluation scenarios." }, status: :unprocessable_entity
  end

  def render_generation_running_error
    render json: { error: 'Evaluation scenarios are already being suggested.' }, status: :unprocessable_entity
  end
end
