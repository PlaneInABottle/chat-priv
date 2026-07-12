require 'securerandom'

class Api::V1::Accounts::Voice::CallsController < Api::V1::Accounts::BaseController
  VALID_PARTICIPANT_TYPES = %w[agent caller].freeze
  MAX_CLIENT_SESSION_ID_LENGTH = 64

  before_action :current_account
  before_action :set_call, except: [:index]
  before_action :ensure_voice_ai_enabled, only: %i[token take_over]

  def index
    authorize Current.account, :show?
    calls = Voice::Calls::Query.new(
      account: Current.account,
      params: filter_params,
      inbox_ids: authorized_inbox_ids
    ).results
    voice_agents_by_id = Current.account.voice_agents.where(id: voice_agent_ids(calls)).index_by(&:id)
    voice_agent_releases_by_id = VoiceAgentRelease.where(
      account_id: Current.account.id,
      id: calls.filter_map(&:voice_agent_release_id)
    ).includes(:voice_agent).index_by(&:id)
    evidence = Voice::Calls::ActivityEvidence.new(calls)
    render json: calls.map { |call| serialize_activity(call, voice_agents_by_id, voice_agent_releases_by_id, evidence) }
  end

  def show
    authorize @call.inbox, :show?
    render json: Voice::CallSerializer.new(@call).payload
  end

  def token
    authorize @call.inbox, :show?
    return render_call_ended if @call.terminal?

    take_over_agent_session_for_token!

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

    take_over_agent_session!
    render json: Voice::CallSerializer.new(@call).payload
  end

  def end
    authorize @call.inbox, :show?
    return render json: Voice::CallSerializer.new(@call).payload if @call.terminal?

    Voice::CallFinalizer.perform!(call: @call, end_reason: params[:end_reason].presence, agent: Current.user)
    render json: Voice::CallSerializer.new(@call).payload
  end

  private

  def filter_params
    params.permit(:inbox_id, :status, :handoff_status, :voice_agent_id, :phone, :from, :to, :limit)
  end

  def authorized_inbox_ids
    policy_scope(Current.account.inboxes).pluck(:id)
  end

  def voice_agent_ids(calls)
    calls.filter_map { |call| call.meta&.fetch('voice_agent_id', nil) }.map(&:to_i).uniq
  end

  def serialize_activity(call, voice_agents_by_id, voice_agent_releases_by_id, evidence)
    Voice::Calls::ActivitySerializer.new(
      call,
      voice_agents_by_id: voice_agents_by_id,
      voice_agent_releases_by_id: voice_agent_releases_by_id,
      evidence: evidence.for(call)
    ).payload
  end

  def set_call
    @call = Current.account.calls.find(params[:id])
  end

  def token_identity
    [
      token_participant_type,
      "account-#{Current.account.id}",
      "user-#{Current.user&.id || 'system'}",
      "call-#{@call.id}",
      "session-#{client_session_id}"
    ].join('-')
  end

  def token_participant_type
    participant_type = params[:participant_type].to_s
    VALID_PARTICIPANT_TYPES.include?(participant_type) ? participant_type : 'agent'
  end

  def agent_token_takeover_required?
    token_participant_type == 'agent' &&
      @call.livekit? &&
      @call.conversation.present? &&
      @call.accepted_by_agent.blank?
  end

  def take_over_agent_session_for_token!
    return unless agent_token_takeover_required?

    take_over_agent_session!
  end

  def take_over_agent_session!
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
