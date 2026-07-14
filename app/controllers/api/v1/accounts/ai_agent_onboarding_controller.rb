class Api::V1::Accounts::AiAgentOnboardingController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :ensure_ai_agent_enabled

  def verify_website
    result = AiAgents::OnboardingWebsiteVerifier.new(
      account: Current.account,
      website_url: params[:website_url]
    ).perform
    render json: result.to_h
  rescue AiAgents::WebsiteCrawler::InvalidWebsite => e
    render json: { error: e.message, code: 'invalid_website' }, status: :unprocessable_entity
  rescue AiAgents::OnboardingWebsiteVerifier::RateLimited => e
    render json: { code: 'website_verification_rate_limited', retry_after: e.retry_after }, status: :too_many_requests
  rescue SafeFetch::Error
    render json: { error: 'Website could not be reached.', code: 'website_unreachable' }, status: :unprocessable_entity
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
    render json: { error: e.message, code: 'invalid_website' }, status: :unprocessable_entity
  rescue AiAgents::WebsiteImportCreator::RateLimited => e
    render json: { code: 'website_import_rate_limited', retry_after: e.retry_after }, status: :too_many_requests
  rescue AiAgents::OnboardingCreator::ExistingAssistant => e
    render json: { error: e.message }, status: :conflict
  end

  private

  def check_authorization
    authorize(AiAgent, :create?)
  end

  def account_params
    params.require(:account).permit(:locale, :website, :website_verification_token, :industry).to_h
  end

  def assistant_params
    params.require(:assistant).permit(:tone).to_h
  end
end
