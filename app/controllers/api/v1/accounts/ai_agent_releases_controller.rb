class Api::V1::Accounts::AiAgentReleasesController < Api::V1::Accounts::BaseController
  RESULTS_PER_PAGE = 25

  before_action :current_account
  before_action :check_admin_authorization?
  before_action :ensure_ai_agent_enabled
  before_action :set_ai_agent
  before_action :set_release, only: [:show, :rollback]

  def index
    releases = @ai_agent.releases
                        .includes(:created_by)
                        .order(revision: :desc)
                        .page(params[:page])
                        .per(RESULTS_PER_PAGE)
    response.headers['X-Total-Count'] = @ai_agent.releases.count.to_s
    render json: releases.map { |release| AssistantReleases::Serializer.new(release).payload }
  end

  def show
    render json: AssistantReleases::Serializer.new(@release, include_snapshot: true).payload
  end

  def rollback
    restored = @ai_agent.rollback_to!(@release, created_by: Current.user)
    render json: AssistantReleases::Serializer.new(restored, include_snapshot: true).payload, status: :created
  end

  private

  def set_ai_agent
    @ai_agent = Current.account.ai_agents.find(params[:ai_agent_id])
  end

  def set_release
    @release = @ai_agent.releases.find(params[:id])
  end
end
