class Voice::CallBroadcaster
  TRANSCRIPT_EVENT = 'voice_call.transcript_segment'
  STATUS_EVENT = 'voice_call.status_changed'
  TOOL_EVENT = 'voice_call.tool_event'

  def self.transcript_segment(call, segment)
    new(call).broadcast(TRANSCRIPT_EVENT, {
                           segment: {
                             id: segment.id,
                             role: segment.role,
                             text: segment.text,
                             source: segment.source,
                             created_at: segment.created_at.iso8601
                           }
                         })
  end

  def self.call_status_changed(call)
    payload = Voice::CallSerializer.new(call).payload.merge(call_id: call.id, account_id: call.account_id)
    new(call).broadcast(STATUS_EVENT, payload)
  end

  def self.tool_event(call, event)
    return unless call.test_call?

    new(call).broadcast(TOOL_EVENT, {
                          event: {
                            id: event.id,
                            tool: event.tool,
                            status: event.status,
                            arguments: event.arguments,
                            result: event.result,
                            error_message: event.error_message,
                            duration_ms: event.duration_ms,
                            source: event.source,
                            created_at: event.created_at.iso8601
                          }.compact
                        })
  end

  def self.safe_call_status_changed(call)
    call_status_changed(call)
  rescue StandardError => e
    Rails.logger.warn("voice broadcast failed event=call_status_changed call_id=#{call.id} error=#{e.message}")
  end

  def initialize(call)
    @call = call
  end

  def broadcast(event_name, extra_payload = {})
    payload = { call_id: call.id, account_id: call.account_id }.merge(extra_payload)
    ActionCable.server.broadcast(account_stream, { event: event_name, data: payload })
  end

  private

  attr_reader :call

  def account_stream
    "account_#{call.account_id}"
  end
end
