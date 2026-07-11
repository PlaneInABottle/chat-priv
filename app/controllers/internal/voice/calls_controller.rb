class Internal::Voice::CallsController < Internal::Voice::BaseController
  BOOTSTRAP_METADATA_KEYS = %i[
    account_id inbox_id voice_number_id voice_inbox_setting_id contact_name sip_call_id sip_trunk_id sip_rule_id
    sip_phone_number sip_trunk_phone_number livekit_inbound_trunk_id livekit_dispatch_rule_id
    from_number to_number phone_number caller_number called_number
  ].freeze
  TRANSCRIPT_METADATA_KEYS = %i[livekit_role external_segment_id].freeze

  before_action :set_call, except: [:agent_context]
  before_action :ensure_runtime_action_allowed, only: %i[transcript tool_call execute_tool handoff]

  def agent_context
    set_or_bootstrap_call
    ensure_runtime_action_allowed
    return if performed?

    render json: VoiceAgents::RuntimeContext.new(call: @call).payload
  end

  def transcript
    segment = Voice::TranscriptAppender.perform!(
      call: @call,
      role: params.require(:role),
      text: params.require(:text),
      source: params[:source].presence || 'livekit_agent',
      confidence: params[:confidence],
      started_at: parse_time(params[:started_at]), ended_at: parse_time(params[:ended_at]),
      external_segment_id: params[:external_segment_id],
      metadata: transcript_metadata_param
    )
    render json: { id: segment.id, call_id: @call.id, status: 'stored' }, status: :created
  end

  def event
    event_name = params.require(:event)
    return if reject_voice_event?(event_name)

    meta = @call.meta || {}
    record_test_call_customer_joined(meta, event_name)
    ai_status = ai_status_for_event(event_name)
    meta['last_voice_agent_event'] = event_name
    meta['last_voice_agent_event_at'] = Time.zone.now.iso8601
    meta['last_voice_agent_payload'] = hash_param(:payload)
    meta['ai_status'] = ai_status if ai_status
    @call.update!(meta: meta)
    schedule_test_call_improvement_budget
    Voice::CallMessageBuilder.new(@call).update_status!(status: @call.status) if @call.message_id
    Voice::CallBroadcaster.safe_call_status_changed(@call)
    render json: { status: 'stored' }
  end

  def tool_call
    event = Voice::ToolCallRecorder.perform!(
      call: @call,
      tool: params.require(:tool),
      status: params[:status].presence || 'executed',
      arguments: hash_param(:arguments),
      result: hash_param(:result),
      error_message: params[:error_message],
      duration_ms: params[:duration_ms],
      external_id: params[:external_id]
    )
    render json: { status: 'stored', tool_event: event }, status: :created
  end

  def execute_tool
    voice_agent = resolve_voice_agent
    execution = VoiceAgents::ToolExecutor.perform!(
      call: @call,
      voice_agent: voice_agent,
      tool_key: params.require(:tool_key),
      args: hash_param(:arguments),
      external_id: params[:external_id]
    )
    render json: execution.except(:tool_event).merge(tool_event: execution[:tool_event])
  end

  def handoff
    return render_test_handoff if @call.test_call? && @call.conversation.blank?
    return render json: { error: 'Call handoff requires a conversation' }, status: :unprocessable_content unless @call.conversation

    setting = voice_setting
    @call.update!(handoff_status: 'requested', ai_status: 'handoff_requested')
    @call.conversation.update!(team: setting&.fallback_team) if setting&.fallback_team
    Voice::ConversationHandoffState.mark_requested!(@call)
    Voice::CallMessageBuilder.new(@call).update_status!(status: @call.status)
    Voice::CallBroadcaster.safe_call_status_changed(@call)
    render json: Voice::CallSerializer.new(@call).payload
  end

  def end
    return render_ignored_dispatch_cancelled_end if ignore_dispatch_cancelled_after_takeover?

    reason = params[:end_reason].presence
    Voice::CallFinalizer.perform!(
      call: @call,
      status: terminal_status,
      end_reason: reason,
      timing: improvement_budget_timing(reason)
    )
    render json: Voice::CallSerializer.new(@call).payload
  end

  private

  def set_call
    @call = find_livekit_call || raise(ActiveRecord::RecordNotFound, 'LiveKit call not found')
    Current.account = @call.account
  end

  def set_or_bootstrap_call
    @call = find_livekit_call
    @call ||= Voice::Telephony::InboundCallBootstrapper.perform!(
      provider_call_id: params[:provider_call_id],
      metadata: bootstrap_metadata_param
    )
    Current.account = @call.account
  end

  def find_livekit_call
    livekit_calls = Call.where(provider: :livekit)
    livekit_calls.find_by(provider_call_id: params[:provider_call_id]) ||
      livekit_calls.where("meta->>'livekit_room_name' = ?", params[:provider_call_id]).first
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  end

  def bootstrap_metadata_param
    permitted_hash_param(:metadata, BOOTSTRAP_METADATA_KEYS)
  end

  def transcript_metadata_param
    permitted_hash_param(:metadata, TRANSCRIPT_METADATA_KEYS)
  end

  def permitted_hash_param(key, permitted_keys)
    value = params[key]
    return {} if value.blank?
    return {} unless value.respond_to?(:permit) || value.is_a?(Hash)

    parameters = value.respond_to?(:permit) ? value : ActionController::Parameters.new(value)
    parameters.permit(*permitted_keys).to_h
  end

  def hash_param(key)
    value = params[key]
    return {} if value.blank?
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    return value if value.is_a?(Hash)

    {}
  end

  def render_test_handoff
    meta = (@call.meta || {}).merge(
      'handoff_status' => 'requested',
      'ai_status' => 'handoff_requested',
      'test_handoff_requested_at' => Time.zone.now.iso8601(3),
      'test_handoff_reason' => params[:reason].to_s
    )
    @call.update!(meta: meta)
    render json: Voice::CallSerializer.new(@call).payload.merge(
      tool_status: 'ok',
      terminal_action: 'handoff',
      test_mode: true,
      customer_message: 'Human handoff requested in the sandbox test call.',
      reason: params[:reason].to_s
    )
  end

  def resolve_voice_agent
    setting = voice_setting
    voice_agent = setting&.voice_agent || @call.account.voice_agents.find_by(id: @call.meta&.fetch('voice_agent_id', nil))
    raise ActiveRecord::RecordNotFound, 'Voice agent not configured' unless voice_agent

    voice_agent
  end

  def voice_setting
    @voice_setting ||= @call.account.voice_inbox_settings.find_by(
      id: @call.meta&.fetch('voice_inbox_setting_id', nil),
      inbox_id: @call.inbox_id
    ) || @call.account.voice_inbox_settings.find_by(inbox_id: @call.inbox_id)
  end

  def terminal_status
    status = params[:status].presence || 'completed'
    Call::TERMINAL_STATUSES.include?(status) ? status : 'completed'
  end

  def improvement_budget_timing(reason)
    duration_limit = @call.meta.to_h['ai_improvement_max_duration_seconds'].to_i
    improvement_started_at = Time.zone.parse(@call.meta.to_h['ai_improvement_started_at'].to_s)
    return {} unless reason == 'ai_improvement_credit_limit' && @call.test_call? && improvement_started_at && duration_limit.positive?

    {
      ended_at: improvement_started_at + duration_limit.seconds,
      duration_seconds: duration_limit
    }
  rescue ArgumentError
    {}
  end

  def ignore_dispatch_cancelled_after_takeover?
    params[:end_reason].to_s == 'livekit_dispatch_cancelled' &&
      @call.livekit? &&
      !@call.terminal? &&
      @call.conversation.present? &&
      @call.handoff_status == 'accepted' &&
      @call.ai_status == 'silent'
  end

  def render_ignored_dispatch_cancelled_end
    @call.update!(
      meta: (@call.meta || {}).merge(
        'last_ignored_voice_agent_end_reason' => params[:end_reason].to_s,
        'last_ignored_voice_agent_end_at' => Time.zone.now.iso8601(3)
      )
    )
    if @call.message_id
      Voice::CallMessageBuilder.new(@call).update_status!(
        status: @call.status,
        agent: @call.accepted_by_agent
      )
    end
    Voice::CallBroadcaster.safe_call_status_changed(@call)
    render json: Voice::CallSerializer.new(@call).payload
  end

  def ensure_runtime_action_allowed
    return render json: { error: 'Voice AI is disabled for this account.' }, status: :forbidden unless @call.account.voice_ai_enabled?
    return render json: { error: 'Call has already ended' }, status: :unprocessable_content if @call.terminal?
  end

  def reject_voice_event?(event_name)
    return false if @call.terminal? && event_name.to_s == 'agent_session_ended'

    ensure_runtime_action_allowed
    performed?
  end

  def record_test_call_customer_joined(meta, event_name)
    return unless event_name.to_s == 'test_call_customer_joined' && @call.test_call?
    return if meta['ai_improvement_started_at'].present?

    meta['ai_improvement_started_at'] = Time.current.iso8601(3)
    @schedule_test_call_improvement_budget = true
  end

  def schedule_test_call_improvement_budget
    return unless @schedule_test_call_improvement_budget

    duration_limit = @call.meta.to_h['ai_improvement_max_duration_seconds'].to_i
    return unless duration_limit.positive?

    Voice::TestCallImprovementBudgetJob.set(wait: duration_limit.seconds).perform_later(@call)
  rescue StandardError => e
    Rails.logger.warn("voice test budget guard scheduling failed call_id=#{@call.id} error=#{e.class.name}: #{e.message}")
  end

  def ai_status_for_event(event_name)
    case event_name.to_s
    when 'agent_session_started', 'agent_listening'
      'active'
    when 'agent_session_ended'
      'completed' if @call.terminal?
    end
  end
end
