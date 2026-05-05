class AiAgentTestConversation < ApplicationRecord
  belongs_to :account
  belongs_to :ai_agent

  validates :account_id, presence: true
  validates :ai_agent_id, presence: true
  validate :messages_must_be_array

  MAX_MESSAGES = 200

  def messages_count
    messages.length
  end

  def last_message_preview
    last = messages.last
    return nil unless last

    last['content'].to_s.truncate(60)
  end

  def append_message(role:, content:)
    ts = Time.current.iso8601(3)
    new_message = { 'id' => SecureRandom.uuid, 'role' => role, 'content' => content, 'created_at' => ts }
    updated_messages = messages + [new_message]
    update!(messages: updated_messages, last_message_at: ts)
    new_message
  end

  def at_message_limit?
    messages.length >= MAX_MESSAGES
  end

  private

  def messages_must_be_array
    errors.add(:messages, 'must be an array') unless messages.is_a?(Array)
  end
end
