class Api::V1::Accounts::AiAgentWebsiteImportsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :ensure_ai_agent_enabled
  before_action :set_ai_agent
  before_action :set_website_import, only: [:show, :apply, :dismiss]

  def index
    @website_imports = @ai_agent.website_imports.latest_first.limit(10)
  end

  def show; end

  def create
    ensure_ai_improvement_credits!(operation: 'website_import', ai_agent: @ai_agent)
    @website_import = AiAgents::WebsiteImportCreator.new(
      ai_agent: @ai_agent,
      website_url: params[:website_url],
      requested_by: Current.user
    ).perform
    render :show, status: :accepted
  rescue AiAgents::WebsiteCrawler::InvalidWebsite => e
    render json: { error: e.message, code: 'invalid_website' }, status: :unprocessable_entity
  rescue AiAgents::WebsiteImportCreator::RateLimited => e
    render json: { code: 'website_import_rate_limited', retry_after: e.retry_after }, status: :too_many_requests
  rescue AiImprovements::Usage::Exhausted => e
    render_ai_improvement_credits_exhausted(e)
  end

  def apply
    AiAgents::WebsiteImportApplier.new(
      website_import: @website_import,
      section_keys: apply_params[:section_keys],
      expected_draft_fingerprint: apply_params[:expected_draft_fingerprint],
      current_document: apply_params[:current_document]&.to_h,
      attach_knowledge: apply_params[:attach_knowledge]
    ).perform
    render :show
  rescue AiAgents::WebsiteImportApplier::Conflict => e
    render json: { error: e.message, code: 'draft_changed' }, status: :conflict
  rescue AiAgents::WebsiteImportApplier::InvalidSelection => e
    render json: { error: e.message, code: e.code }, status: :unprocessable_entity
  end

  def dismiss
    dismissed = @website_import.with_lock do
      next false unless @website_import.ready?

      @website_import.update!(
        status: :dismissed,
        stage: :complete,
        base_document: nil,
        proposed_sections: {},
        proposed_knowledge_content: nil,
        completed_at: Time.current
      )
      true
    end
    return render json: { code: 'invalid_selection' }, status: :unprocessable_entity unless dismissed

    render :show
  end

  private

  def check_authorization
    policy_action = {
      'index' => :index?,
      'show' => :show?,
      'create' => :create?,
      'apply' => :update?,
      'dismiss' => :update?
    }.fetch(action_name)
    authorize(AiAgent, policy_action)
  end

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def set_website_import
    @website_import = @ai_agent.website_imports.find(params[:id])
  end

  def apply_params
    params.permit(:expected_draft_fingerprint, :attach_knowledge, section_keys: [], current_document: {})
  end
end
