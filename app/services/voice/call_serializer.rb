class Voice::CallSerializer
  def initialize(call)
    @call = call
  end

  def payload
    identity_payload.merge(state_payload).merge(
      transcript_segments: transcript_segments,
      tool_events: tool_events
    )
  end

  private

  attr_reader :call

  def identity_payload
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

  def state_payload
    {
      status: call.display_status,
      test_call: call.test_call?,
      test_call_source: call.test_call_source,
      test_call_initiated_by_user_id: call.test_call_initiated_by_user_id,
      handoff_status: call.handoff_status,
      ai_status: call.ai_status,
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

  def tool_events
    call.voice_tool_events.order(:created_at).map do |event|
      {
        id: event.id,
        tool: event.tool,
        status: event.status,
        arguments: event.arguments,
        result: event.result,
        error_message: event.error_message,
        duration_ms: event.duration_ms,
        source: event.source,
        created_at: event.created_at.iso8601
      }
    end
  end
end
