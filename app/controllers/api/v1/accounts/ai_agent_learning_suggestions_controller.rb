class Api::V1::Accounts::AiAgentLearningSuggestionsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_authorization
  before_action :ensure_ai_agent_enabled
  before_action :set_ai_agent
  before_action :set_learning_suggestion, only: [:apply, :dismiss]

  def index
    @learning_suggestions = @ai_agent.learning_suggestions
                                     .includes(:conversation, :source_message, :submitted_by, :reviewed_by)
                                     .order(created_at: :desc)
                                     .limit(50)
  end

  def apply
    AiAgents::LearningSuggestionApplier.new(
      suggestion: @learning_suggestion,
      reviewer: Current.user,
      review: {
        instruction: review_params[:suggested_instruction],
        destination: review_params[:destination],
        target_section: review_params[:target_section],
        source_name: review_params[:source_name]
      }
    ).perform
    render :show
  rescue AiAgents::LearningSuggestionApplier::InvalidSuggestion => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def dismiss
    return render_applied_error if @learning_suggestion.applied?

    @learning_suggestion.update!(
      status: :dismissed,
      reviewed_by: Current.user,
      reviewed_at: Time.current
    )
    render :show
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def set_learning_suggestion
    @learning_suggestion = @ai_agent.learning_suggestions.find(params[:id])
  end

  def review_params
    params.permit(:suggested_instruction, :destination, :target_section, :source_name)
  end

  def render_applied_error
    render json: { error: 'Applied suggestions cannot be dismissed.' }, status: :unprocessable_entity
  end
end
