class Api::V1::Accounts::AiAgentEvaluationRunsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :ensure_ai_agent_enabled
  before_action :set_ai_agent
  before_action :set_evaluation_run, only: [:show]

  def index
    @evaluation_runs = @ai_agent.evaluation_runs.includes(:evaluation_results).order(created_at: :desc).limit(10)
  end

  def show; end

  def create
    return render_empty_suite_error if @ai_agent.evaluation_cases.none?
    return render_running_error if @ai_agent.evaluation_runs.pending.or(@ai_agent.evaluation_runs.running).exists?

    ensure_ai_improvement_credits!(operation: 'evaluation', ai_agent: @ai_agent)
    create_evaluation_run
    AiAgents::EvaluationRunJob.perform_later(@evaluation_run)
    render :show, status: :accepted
  rescue ActiveRecord::RecordNotUnique
    render_running_error
  rescue AiImprovements::Usage::Exhausted => e
    render_ai_improvement_credits_exhausted(e)
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def set_evaluation_run
    @evaluation_run = @ai_agent.evaluation_runs.includes(:evaluation_results).find(params[:id])
  end

  def create_evaluation_run
    AiAgentEvaluationRun.transaction do
      cases = @ai_agent.evaluation_cases.order(:position, :created_at).to_a
      @evaluation_run = @ai_agent.evaluation_runs.create!(
        account: Current.account,
        status: :pending,
        prompt_snapshot: @ai_agent.prompt,
        config_snapshot: runtime_config_snapshot,
        knowledge_snapshot: AiKnowledgeSources::Snapshot.for(@ai_agent),
        draft_fingerprint: @ai_agent.draft_fingerprint,
        total_count: cases.length
      )
      cases.each { |evaluation_case| create_result(evaluation_case) }
    end
  end

  def create_result(evaluation_case)
    @evaluation_run.evaluation_results.create!(
      evaluation_case: evaluation_case,
      status: :pending,
      case_name: evaluation_case.name,
      customer_message: evaluation_case.customer_message,
      success_criteria: evaluation_case.success_criteria
    )
  end

  def runtime_config_snapshot
    @ai_agent.config.to_h.deep_stringify_keys.except('instructions')
  end

  def render_empty_suite_error
    render json: { error: 'Add at least one evaluation scenario before running the suite.' }, status: :unprocessable_entity
  end

  def render_running_error
    render json: { error: 'An evaluation run is already in progress.' }, status: :unprocessable_entity
  end
end
