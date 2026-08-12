# frozen_string_literal: true

# == Schema Information
#
# Table name: ai_agent_response_slots
#
#  id                      :bigint           not null, primary key
#  status                  :integer          default("reserved"), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  ai_agent_usage_event_id :bigint           not null
#  trigger_message_id      :bigint           not null
#
# Indexes
#
#  idx_ai_agent_response_slots_on_event_status          (ai_agent_usage_event_id,status)
#  idx_ai_agent_response_slots_on_event_trigger         (ai_agent_usage_event_id,trigger_message_id) UNIQUE
#  index_ai_agent_response_slots_on_trigger_message_id  (trigger_message_id)
#
# Foreign Keys
#
#  fk_rails_...  (ai_agent_usage_event_id => ai_agent_usage_events.id) ON DELETE => cascade
#  fk_rails_...  (trigger_message_id => messages.id) ON DELETE => cascade
#
# A reserved response slot for one customer-visible AI response within a usage
# event's reuse window. Keyed uniquely by (event, trigger message) so duplicate
# or retried jobs always transition the same row.
class AiAgentResponseSlot < ApplicationRecord
  enum status: { reserved: 0, consumed: 1, released: 2, handed_off: 3 }

  belongs_to :ai_agent_usage_event
  belongs_to :trigger_message, class_name: 'Message'

  validates :status, presence: true
  validate :trigger_message_belongs_to_account

  scope :active, -> { where(status: %i[reserved consumed]) }
  scope :consumed, -> { where(status: :consumed) }
  scope :for_trigger, ->(trigger_message_id) { where(trigger_message_id: trigger_message_id) }

  private

  def trigger_message_belongs_to_account
    return if ai_agent_usage_event.blank? || trigger_message.blank?
    return if ai_agent_usage_event.account_id == trigger_message.account_id

    errors.add(:trigger_message, 'must belong to account')
  end
end
