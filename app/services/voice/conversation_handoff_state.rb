# frozen_string_literal: true

class Voice::ConversationHandoffState
  STATUS_KEY = 'voice_ai_handoff_status'
  CALL_ID_KEY = 'voice_ai_handoff_call_id'
  REQUESTED_AT_KEY = 'voice_ai_handoff_requested_at'
  ACCEPTED_AT_KEY = 'voice_ai_handoff_accepted_at'

  def self.mark_requested!(call)
    new(call).mark_requested!
  end

  def self.mark_accepted!(call)
    new(call).mark_accepted!
  end

  def self.clear_if_current!(call)
    new(call).clear_if_current!
  end

  def initialize(call)
    @call = call
  end

  def mark_requested!
    update_attributes do |attributes|
      attributes[STATUS_KEY] = 'requested'
      attributes[CALL_ID_KEY] = call.id
      attributes[REQUESTED_AT_KEY] = Time.zone.now.iso8601(3)
      attributes.delete(ACCEPTED_AT_KEY)
    end
  end

  def mark_accepted!
    update_attributes do |attributes|
      attributes[STATUS_KEY] = 'accepted'
      attributes[CALL_ID_KEY] = call.id
      attributes[ACCEPTED_AT_KEY] = Time.zone.now.iso8601(3)
    end
  end

  def clear_if_current!
    update_attributes do |attributes|
      next unless current_call?(attributes)

      attributes.delete(STATUS_KEY)
      attributes.delete(CALL_ID_KEY)
      attributes.delete(REQUESTED_AT_KEY)
      attributes.delete(ACCEPTED_AT_KEY)
    end
  end

  private

  attr_reader :call

  def update_attributes
    return unless call.conversation

    attributes = (call.conversation.additional_attributes || {}).dup
    yield attributes
    call.conversation.update!(additional_attributes: attributes)
  end

  def current_call?(attributes)
    attributes[CALL_ID_KEY].blank? || attributes[CALL_ID_KEY].to_i == call.id
  end
end
