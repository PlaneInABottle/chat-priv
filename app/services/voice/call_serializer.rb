class Voice::CallSerializer
  def initialize(call)
    @call = call
  end

  def payload
    identity_payload.merge(state_payload).merge(
      recording: recording_payload,
      recording_url: recording_payload[:url],
      transcript_segments: transcript_segments,
      tool_event_summaries: tool_event_summaries,
      tool_events: test_tool_events
    ).compact
  end

  private

  attr_reader :call

  def identity_payload
    base_identity_payload.merge(voice_identity_payload)
  end

  def base_identity_payload
    {
      id: call.id,
      provider: call.provider,
      provider_call_id: call.provider_call_id,
      direction: call.direction,
      account_id: call.account_id,
      inbox_id: call.inbox_id,
      conversation_id: call.conversation&.display_id,
      contact_id: call.contact_id,
      message_id: call.message_id,
      livekit_room_name: call.livekit_room_name
    }
  end

  def voice_identity_payload
    {
      voice_agent_id: call.meta&.fetch('voice_agent_id', nil),
      voice_agent_name: voice_agent&.name,
      voice_number_id: call.meta&.fetch('voice_number_id', nil),
      voice_provider_connection_id: call.meta&.fetch('voice_provider_connection_id', nil)
    }
  end

  def state_payload
    {
      status: call.display_status,
      test_call: call.test_call?,
      test_call_source: call.test_call_source,
      test_call_initiated_by_user_id: call.test_call_initiated_by_user_id,
      handoff_status: call.handoff_status,
      ai_status: call.ai_status,
      summary: summary_payload,
      started_at: call.started_at&.iso8601,
      duration_seconds: call.duration_seconds,
      end_reason: call.end_reason
    }
  end

  def transcript_segments
    call.transcript_segments.order(:created_at, :id).map do |segment|
      {
        id: segment.id,
        role: segment.role,
        source: segment.source,
        text: segment.text,
        confidence: segment.confidence,
        started_at: segment.started_at&.iso8601,
        ended_at: segment.ended_at&.iso8601,
        created_at: segment.created_at.iso8601
      }
    end
  end

  def recording_payload
    @recording_payload ||= build_recording_payload
  end

  def build_recording_payload
    recording = VoiceRecording.where(call_id: call.id).latest_first.first
    return { status: 'disabled', url: call.recording_url }.compact unless recording

    {
      id: recording.id,
      status: recording.status,
      storage_provider: recording.storage_provider,
      content_type: recording.content_type,
      duration_seconds: recording.duration_seconds,
      started_at: recording.started_at&.iso8601,
      completed_at: recording.completed_at&.iso8601,
      error_message: recording.error_message,
      url: recording.completed? ? Voice::Recordings::StorageConfig.new.signed_url(recording) : nil
    }.compact
  end

  def test_tool_events
    return unless call.test_call?

    voice_tool_events.map do |event|
      {
        id: event.id,
        tool: event.tool,
        status: event.status,
        arguments: redact_tool_payload(event.arguments),
        result: redact_tool_payload(event.result),
        error_message: event.error_message,
        duration_ms: event.duration_ms,
        source: event.source,
        created_at: event.created_at.iso8601
      }.compact
    end
  end

  def tool_event_summaries
    voice_tool_events.map do |event|
      {
        id: event.id,
        tool: event.tool,
        status: event.status,
        error_message: event.error_message,
        duration_ms: event.duration_ms,
        source: event.source,
        created_at: event.created_at.iso8601
      }.compact
    end
  end

  def redact_tool_payload(value)
    case value
    when Hash
      value.transform_values { |item| redact_tool_payload(item) }
    when Array
      value.map { |item| redact_tool_payload(item) }
    when String
      AiAgents::PrivacyRedactor.redact_text(value)
    else
      value
    end
  end

  def summary_payload
    summary = call.summary
    return if summary.blank?
    return { text: AiAgents::PrivacyRedactor.redact_text(summary) } if summary.is_a?(String)

    summary.slice('text', 'generated_at', 'source', 'model').tap do |payload|
      payload['text'] = AiAgents::PrivacyRedactor.redact_text(payload['text']) if payload['text'].present?
    end
  end

  def voice_agent
    return @voice_agent if defined?(@voice_agent)

    voice_agent_id = call.meta&.fetch('voice_agent_id', nil)
    @voice_agent = voice_agent_id ? call.account.voice_agents.find_by(id: voice_agent_id) : nil
  end

  def voice_tool_events
    @voice_tool_events ||= VoiceToolEvent.where(call_id: call.id).order(:created_at, :id)
  end
end
