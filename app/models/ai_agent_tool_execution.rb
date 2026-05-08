# == Schema Information
#
# Table name: ai_agent_tool_executions
#
class AiAgentToolExecution < ApplicationRecord
  enum status: { executed: 0, error: 1, rejected: 2 }
  enum mode: { test: 0, live: 1 }

  belongs_to :account
  belongs_to :ai_agent
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true

  validates :tool_key, :mode, :status, presence: true
  validate :ai_agent_belongs_to_account
  validate :conversation_belongs_to_account
  validate :message_belongs_to_account
  validate :message_belongs_to_conversation

  private

  def ai_agent_belongs_to_account
    return if ai_agent.blank? || account.blank? || ai_agent.account_id == account_id

    errors.add(:ai_agent, 'must belong to account')
  end

  def conversation_belongs_to_account
    return if conversation.blank? || account.blank? || conversation.account_id == account_id

    errors.add(:conversation, 'must belong to account')
  end

  def message_belongs_to_account
    return if message.blank? || account.blank? || message.account_id == account_id

    errors.add(:message, 'must belong to account')
  end

  def message_belongs_to_conversation
    return if message.blank? || conversation.blank? || message.conversation_id == conversation_id

    errors.add(:message, 'must belong to conversation')
  end
end
