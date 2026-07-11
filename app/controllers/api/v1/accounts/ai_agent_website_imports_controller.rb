class Api::V1::Accounts::AiAgentWebsiteImportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :ensure_ai_agent_enabled
  before_action :set_ai_agent
  before_action :set_website_import, only: [:show, :apply]

  def index
    @website_imports = @ai_agent.website_imports.latest_first.limit(10)
  end

  def show; end

  def create
    @website_import = AiAgents::WebsiteImportCreator.new(
      ai_agent: @ai_agent,
      website_url: params[:website_url],
      requested_by: Current.user,
      mode: :preview
    ).perform
    render :show, status: :accepted
  rescue AiAgents::WebsiteCrawler::InvalidWebsite => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def apply
    AiAgents::WebsiteImportApplier.new(
      website_import: @website_import,
      section_keys: params[:section_keys],
      expected_draft_fingerprint: params[:expected_draft_fingerprint]
    ).perform
    render :show
  rescue AiAgents::WebsiteImportApplier::Conflict => e
    render json: { error: e.message, code: 'draft_changed' }, status: :conflict
  rescue AiAgents::WebsiteImportApplier::InvalidSelection => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def check_authorization
    policy_action = { 'index' => :index?, 'show' => :show?, 'create' => :create?, 'apply' => :update? }.fetch(action_name)
    authorize(AiAgent, policy_action)
  end

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def set_website_import
    @website_import = @ai_agent.website_imports.find(params[:id])
  end
end
