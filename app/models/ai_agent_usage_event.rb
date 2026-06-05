# == Schema Information
#
# Table name: ai_agent_usage_events
#
#  id                :bigint           not null, primary key
#  period            :integer          default("monthly"), not null
#  period_end_at     :datetime         not null
#  period_start_at   :datetime         not null
#  status            :integer          default("reserved"), not null
#  window_ends_at    :datetime         not null
#  window_started_at :datetime         not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  ai_agent_id       :bigint           not null
#  contact_id        :bigint
#  conversation_id   :bigint
#  message_id        :bigint
#
# Indexes
#
#  idx_ai_agent_usage_events_on_account_contact_window   (account_id,contact_id,window_ends_at)
#  idx_ai_agent_usage_events_on_account_period_status    (account_id,period,period_start_at,status)
#  idx_ai_agent_usage_events_on_conversation_created_at  (conversation_id,created_at)
#  index_ai_agent_usage_events_on_account_id             (account_id)
#  index_ai_agent_usage_events_on_ai_agent_id            (ai_agent_id)
#  index_ai_agent_usage_events_on_contact_id             (contact_id)
#  index_ai_agent_usage_events_on_conversation_id        (conversation_id)
#  index_ai_agent_usage_events_on_message_id             (message_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_agent_id => ai_agents.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => nullify
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => nullify
#  fk_rails_...  (message_id => messages.id) ON DELETE => nullify
#
class AiAgentUsageEvent < ApplicationRecord
  enum period: { monthly: 0 }
  enum status: { reserved: 0, consumed: 1, released: 2 }

  belongs_to :account
  belongs_to :ai_agent
  belongs_to :contact, optional: true
  belongs_to :conversation, optional: true
  belongs_to :message, optional: true

  validates :period, :period_start_at, :period_end_at, :window_started_at, :window_ends_at, :status, presence: true
  validate :ai_agent_belongs_to_account
  validate :conversation_belongs_to_account
  validate :message_belongs_to_account

  scope :active, -> { where(status: %i[reserved consumed]) }
  scope :for_period, ->(period_start_at) { where(period: :monthly, period_start_at: period_start_at) }
  scope :active_for_contact_window, lambda { |account_id:, contact_id:, at:|
    active.where(account_id: account_id, contact_id: contact_id).where('window_ends_at > ?', at)
  }

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
end
