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

  def handoff
    setting = VoiceInboxSetting.find_by(id: @call.meta['voice_inbox_setting_id'])
    @call.update!(handoff_status: 'requested', ai_status: 'handoff_requested')
    @call.conversation.update!(team: setting&.fallback_team) if setting&.fallback_team
    render json: Voice::CallSerializer.new(@call).payload
  end

  def end
    duration = @call.started_at ? (Time.zone.now - @call.started_at).to_i : nil
    @call.update!(
      status: terminal_status,
      ended_at: Time.zone.now.to_i,
      duration_seconds: duration,
      end_reason: params[:end_reason].presence
    )
    Voice::CallMessageBuilder.new(@call).update_status!(status: @call.status, duration_seconds: duration)
    render json: Voice::CallSerializer.new(@call).payload
  end

  private

  def set_call
    @call = Call.livekit.find_by(provider_call_id: params[:provider_call_id]) ||
            Call.livekit.where("meta->>'livekit_room_name' = ?", params[:provider_call_id]).first!
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

  def terminal_status
    status = params[:status].presence || 'completed'
    Call::TERMINAL_STATUSES.include?(status) ? status : 'completed'
  end
end
