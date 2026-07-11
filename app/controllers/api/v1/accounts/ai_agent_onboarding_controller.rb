class Api::V1::Accounts::AiAgentOnboardingController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :ensure_ai_agent_enabled

  def show
    load_onboarding_state
  end

  def create
    result = AiAgents::OnboardingCreator.new(
      account: Current.account,
      user: Current.user,
      account_attributes: account_params,
      assistant_attributes: assistant_params
    ).perform
    @ai_agent = result.ai_agent
    @website_import = result.website_import
    render :show, status: :accepted
  rescue AiAgents::WebsiteCrawler::InvalidWebsite => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue AiAgents::OnboardingCreator::ExistingAssistant => e
    render json: { error: e.message }, status: :conflict
  end

  def complete
    load_onboarding_state
    return render json: { error: 'No onboarding assistant was found.' }, status: :not_found unless @ai_agent

    Current.account.custom_attributes.delete('onboarding_step')
    Current.account.save!
    render json: { ai_agent_id: @ai_agent.id }
  end

  private

  def check_authorization
    authorize(AiAgent, action_name == 'create' ? :create? : :show?)
  end

  def load_onboarding_state
    @ai_agent = Current.account.ai_agents
                       .where("config -> 'setup_profile' ->> 'source' = ?", 'account_onboarding')
                       .order(:id)
                       .first
    @website_import = @ai_agent&.website_imports&.latest_first&.first
  end

  def account_params
    params.require(:account).permit(:locale, :website, :industry, :company_size, :timezone, :referral_source, :user_role).to_h
  end

  def assistant_params
    params.require(:assistant).permit(:purpose, :tone).to_h
  end
end
