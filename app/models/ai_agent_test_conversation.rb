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
  class InvalidSelection < StandardError; end

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

  def submit_option!(message_id:, selected_value:)
    with_lock do
      message_index, prompt = option_prompt!(message_id)
      item = selected_option!(prompt, selected_value)
      raise InvalidSelection, 'This question has already been answered.' if prompt['submitted_values'].present?

      persist_option_selection!(message_index, prompt, item)
      item['title']
    end
  end

  def at_message_limit?
    messages.length >= MAX_MESSAGES
  end

  private

  def option_prompt!(message_id)
    message_index = messages.index { |message| message['id'].to_s == message_id.to_s }
    raise InvalidSelection, 'Option prompt was not found.' unless message_index

    [message_index, messages.fetch(message_index).deep_dup]
  end

  def selected_option!(prompt, selected_value)
    valid_prompt = prompt['role'] == 'assistant' && prompt['terminal_action'] == AiAgents::Config::PRESENT_OPTIONS_TOOL
    item = Array(prompt.dig('tool_result', 'presentation', 'items')).find do |candidate|
      candidate['value'].to_s == selected_value.to_s
    end
    raise InvalidSelection, 'Selected option is not available.' unless valid_prompt && item

    item
  end

  def persist_option_selection!(message_index, prompt, item)
    prompt['submitted_values'] = [item.slice('title', 'value')]
    updated_messages = messages.deep_dup
    updated_messages[message_index] = prompt
    update!(messages: updated_messages)
  end

  def messages_must_be_array
    errors.add(:messages, 'must be an array') unless messages.is_a?(Array)
  end

  def preview_content(message)
    return message['content'] if message['content'].present?
    return message.dig('tool_result', 'customer_message') if message.dig('terminal_action') == 'handoff'

    nil
  end
end
