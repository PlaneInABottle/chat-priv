class Internal::Voice::CallsController < Internal::Voice::BaseController
  before_action :set_call

  def transcript
    segment = Voice::TranscriptAppender.perform!(
      call: @call,
      role: params.require(:role),
      text: params.require(:text),
      source: params[:source].presence || 'livekit_agent',
      confidence: params[:confidence],
      started_at: parse_time(params[:started_at]),
      ended_at: parse_time(params[:ended_at]),
      external_segment_id: params[:external_segment_id],
      metadata: metadata_param
    )
    render json: { id: segment.id, call_id: @call.id, status: 'stored' }, status: :created
  end

  def event
    meta = @call.meta || {}
    event_name = params.require(:event)
    meta['last_voice_agent_event'] = event_name
    meta['last_voice_agent_event_at'] = Time.zone.now.iso8601
    meta['last_voice_agent_payload'] = params[:payload] if params[:payload].is_a?(Hash)
    @call.update!(meta: meta)
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

  def handoff
    return render_test_handoff if @call.test_call? && @call.conversation.blank?
    return render json: { error: 'Call handoff requires a conversation' }, status: :unprocessable_content unless @call.conversation

    setting = VoiceInboxSetting.find_by(id: @call.meta['voice_inbox_setting_id'])
    @call.update!(handoff_status: 'requested', ai_status: 'handoff_requested')
    @call.conversation.update!(team: setting&.fallback_team) if setting&.fallback_team
    Voice::CallMessageBuilder.new(@call).update_status!(status: @call.status)
    Voice::CallBroadcaster.safe_call_status_changed(@call)
    render json: Voice::CallSerializer.new(@call).payload
  end

  def end
    Voice::CallFinalizer.perform!(
      call: @call,
      status: terminal_status,
      end_reason: params[:end_reason].presence
    )
    render json: Voice::CallSerializer.new(@call).payload
  end

  private

  def set_call
    livekit_calls = Call.where(provider: :livekit)
    @call = livekit_calls.find_by(provider_call_id: params[:provider_call_id]) ||
            livekit_calls.where("meta->>'livekit_room_name' = ?", params[:provider_call_id]).first!
    Current.account = @call.account
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value.to_s)
  end

  def metadata_param
    metadata = params[:metadata]
    return {} if metadata.blank?
    return metadata.to_unsafe_h if metadata.respond_to?(:to_unsafe_h)
    return metadata if metadata.is_a?(Hash)

    {}
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

  def terminal_status
    status = params[:status].presence || 'completed'
    Call::TERMINAL_STATUSES.include?(status) ? status : 'completed'
  end
end
