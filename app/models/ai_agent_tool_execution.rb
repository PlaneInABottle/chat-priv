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

  private

  def ai_agent_belongs_to_account
    return if ai_agent.blank? || account.blank? || ai_agent.account_id == account_id

    errors.add(:ai_agent, 'must belong to account')
  end
end
