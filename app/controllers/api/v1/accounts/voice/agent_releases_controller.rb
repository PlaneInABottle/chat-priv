class Api::V1::Accounts::Voice::AgentReleasesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :check_admin_authorization?
  before_action :ensure_voice_ai_enabled
  before_action :set_voice_agent
  before_action :set_release, only: [:show, :rollback]

  def index
    releases = @voice_agent.releases.includes(:created_by).order(revision: :desc)
    render json: releases.map { |release| AssistantReleases::Serializer.new(release).payload }
  end

  def show
    render json: release_payload(@release, include_snapshot: true)
  end

  def rollback
    restored = @voice_agent.rollback_to!(@release, created_by: Current.user)
    render json: release_payload(restored, include_snapshot: true), status: :created
  end

  private

  def set_voice_agent
    @voice_agent = Current.account.voice_agents.find(params[:agent_id])
  end

  def set_release
    @release = @voice_agent.releases.find(params[:id])
  end

  def release_payload(release, include_snapshot: false)
    payload = AssistantReleases::Serializer.new(release, include_snapshot: include_snapshot).payload
    return payload unless include_snapshot

    payload.merge(snapshot: VoiceAgents::ReleaseSnapshot.sanitize(release.snapshot))
  end
end
