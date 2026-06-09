# == Schema Information
#
# Table name: ai_agent_test_conversations
#
#  id              :bigint           not null, primary key
#  last_message_at :datetime
#  messages        :jsonb            not null
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  ai_agent_id     :bigint           not null
#
# Indexes
#
#  index_ai_agent_test_conversations_on_account_id       (account_id)
#  index_ai_agent_test_conversations_on_ai_agent_id      (ai_agent_id)
#  index_ai_agent_test_conversations_on_last_message_at  (last_message_at)
#
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

    preview_content(last).to_s.truncate(60)
  end

  def append_message(role:, content:, metadata: {})
    ts = Time.current.iso8601(3)
    new_message = {
      'id' => SecureRandom.uuid,
      'role' => role,
      'content' => content,
      'created_at' => ts
    }.merge(metadata.deep_stringify_keys)
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

  def preview_content(message)
    return message['content'] if message['content'].present?
    return message.dig('tool_result', 'customer_message') if message.dig('terminal_action') == 'handoff'

    nil
  end
end
