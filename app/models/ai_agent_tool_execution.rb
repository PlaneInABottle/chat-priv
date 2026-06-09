# == Schema Information
#
# Table name: ai_agent_tool_executions
#
#  id              :bigint           not null, primary key
#  arguments       :jsonb            not null
#  duration_ms     :integer
#  error_code      :string
#  error_message   :text
#  mode            :integer          not null
#  result          :jsonb            not null
#  status          :integer          not null
#  terminal        :boolean          default(FALSE), not null
#  tool_key        :string           not null
#  tool_name       :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  ai_agent_id     :bigint           not null
#  conversation_id :bigint
#  message_id      :bigint
#  tool_call_id    :string
#
# Indexes
#
#  index_ai_agent_tool_executions_on_account_id                  (account_id)
#  index_ai_agent_tool_executions_on_account_id_and_created_at   (account_id,created_at)
#  index_ai_agent_tool_executions_on_ai_agent_id                 (ai_agent_id)
#  index_ai_agent_tool_executions_on_ai_agent_id_and_created_at  (ai_agent_id,created_at)
#  index_ai_agent_tool_executions_on_conversation_id             (conversation_id)
#  index_ai_agent_tool_executions_on_message_id                  (message_id)
#  index_ai_agent_tool_executions_on_tool_key                    (tool_key)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_agent_id => ai_agents.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => nullify
#  fk_rails_...  (message_id => messages.id) ON DELETE => nullify
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
