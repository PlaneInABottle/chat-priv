class Voice::CallMessageBuilder
  def initialize(call)
    @call = call
  end

  def perform!
    return unless call.conversation

    call.message || create_message!
  end

  def update_status!(status:, agent: nil, duration_seconds: nil)
    message = call.message
    return unless message

    patch = build_data_payload.merge(
      'status' => status&.to_s&.tr('_', '-'),
      'accepted_by' => agent && { 'id' => agent.id, 'name' => agent.name }
    ).compact
    patch['duration_seconds'] = duration_seconds if duration_seconds

    message.update!(content_attributes: (message.content_attributes || {}).deep_merge('data' => patch))
    message
  end

  private

  attr_reader :call

  def create_message!
    params = {
      content: I18n.t("conversations.messages.voice_call.#{call.provider}"),
      message_type: call.outgoing? ? 'outgoing' : 'incoming',
      content_type: 'voice_call',
      content_attributes: { 'data' => build_data_payload }
    }
    Messages::MessageBuilder.new(sender, call.conversation, params).perform
  end

  def sender
    call.outgoing? ? call.accepted_by_agent : call.contact
  end

  def build_data_payload
    {
      'call_id' => call.id,
      'call_sid' => call.provider_call_id,
      'call_source' => call.provider,
      'call_direction' => call.direction_label,
      'status' => call.display_status,
      'livekit_room_name' => call.livekit_room_name,
      'test_call' => call.test_call?,
      'test_call_source' => call.test_call_source,
      'test_call_initiated_by_user_id' => call.test_call_initiated_by_user_id,
      'handoff_status' => call.handoff_status,
      'ai_status' => call.ai_status,
      'duration_seconds' => call.duration_seconds
    }.compact
  end
end
