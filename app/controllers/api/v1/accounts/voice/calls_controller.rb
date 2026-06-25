require 'securerandom'

class Api::V1::Accounts::Voice::CallsController < Api::V1::Accounts::BaseController
  VALID_PARTICIPANT_TYPES = %w[agent caller].freeze
  MAX_CLIENT_SESSION_ID_LENGTH = 64

  before_action :current_account
  before_action :set_call
  before_action :ensure_voice_ai_enabled, only: %i[token take_over]

  def show
    authorize @call.inbox, :show?
    render json: Voice::CallSerializer.new(@call).payload
  end

  def token
    authorize @call.inbox, :show?
    return render_call_ended if @call.terminal?

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
    return render_call_ended if @call.terminal?
    return render_conversation_required unless @call.conversation

    room_result = Voice::Livekit::RoomService.remove_agent_participants(call: @call)
    meta = (@call.meta || {}).merge(
      'handoff_status' => 'accepted',
      'ai_status' => 'silent',
      'livekit_agent_removal' => room_result
    )
    @call.update!(
      accepted_by_agent: Current.user,
      status: 'in_progress',
      meta: meta
    )
    Voice::ConversationHandoffState.mark_accepted!(@call)
    @call.conversation.update!(assignee: Current.user)
    Voice::CallMessageBuilder.new(@call).update_status!(status: @call.status, agent: Current.user)
    Voice::CallBroadcaster.safe_call_status_changed(@call)
    render json: Voice::CallSerializer.new(@call).payload
  end

  def end
    authorize @call.inbox, :show?
    return render json: Voice::CallSerializer.new(@call).payload if @call.terminal?

    Voice::CallFinalizer.perform!(call: @call, end_reason: params[:end_reason].presence, agent: Current.user)
    render json: Voice::CallSerializer.new(@call).payload
  end

  private

  def set_call
    @call = Current.account.calls.find(params[:id])
  end

  def token_identity
    prefix = VALID_PARTICIPANT_TYPES.include?(params[:participant_type].to_s) ? params[:participant_type].to_s : 'agent'
    [
      prefix,
      "account-#{Current.account.id}",
      "user-#{Current.user&.id || 'system'}",
      "call-#{@call.id}",
      "session-#{client_session_id}"
    ].join('-')
  end

  def client_session_id
    sanitized = params[:client_session_id].to_s.downcase.gsub(/[^a-z0-9-]/, '').first(MAX_CLIENT_SESSION_ID_LENGTH)
    sanitized.presence || SecureRandom.uuid
  end

  def render_call_ended
    render json: { error: 'Call has already ended' }, status: :unprocessable_content
  end

  def render_conversation_required
    render json: { error: 'Call handoff requires a conversation' }, status: :unprocessable_content
  end
end
