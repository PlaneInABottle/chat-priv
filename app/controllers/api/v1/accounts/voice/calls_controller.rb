class Api::V1::Accounts::Voice::CallsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :set_call

  def show
    authorize @call.inbox, :show?
    render json: Voice::CallSerializer.new(@call).payload
  end

  def token
    authorize @call.inbox, :show?
    render json: Voice::Livekit::TokenService.new(
      call: @call,
      identity: token_identity,
      name: Current.user&.available_name || Current.user&.name || token_identity
    ).payload
  rescue KeyError => e
    render json: { error: "#{e.key} is not configured" }, status: :unprocessable_entity
  end

  def take_over
    authorize @call.inbox, :show?
    @call.update!(accepted_by_agent: Current.user, handoff_status: 'accepted', ai_status: 'silent', status: 'in_progress')
    @call.conversation.update!(assignee: Current.user)
    Voice::CallMessageBuilder.new(@call).update_status!(status: @call.status, agent: Current.user)
    render json: Voice::CallSerializer.new(@call).payload
  end

  def end
    authorize @call.inbox, :show?
    duration = @call.started_at ? (Time.zone.now - @call.started_at).to_i : nil
    @call.update!(status: 'completed', ended_at: Time.zone.now.to_i, duration_seconds: duration, end_reason: params[:end_reason].presence)
    Voice::CallMessageBuilder.new(@call).update_status!(status: @call.status, agent: @call.accepted_by_agent, duration_seconds: duration)
    render json: Voice::CallSerializer.new(@call).payload
  end

  private

  def set_call
    @call = Current.account.calls.find(params[:id])
  end

  def token_identity
    prefix = params[:participant_type].presence || 'agent'
    "#{prefix}-account-#{Current.account.id}-user-#{Current.user&.id || 'system'}-call-#{@call.id}"
  end
end
