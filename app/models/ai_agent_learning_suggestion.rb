# == Schema Information
#
# Table name: ai_agent_learning_suggestions
#
#  id                    :bigint           not null, primary key
#  applied_at            :datetime
#  customer_message      :text             not null
#  error_message         :text
#  human_answer          :text             not null
#  reason                :text
#  reviewed_at           :datetime
#  status                :integer          default("pending"), not null
#  suggested_instruction :text
#  target_section        :string
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  ai_agent_id           :bigint           not null
#  conversation_id       :bigint
#  reviewed_by_id        :bigint
#  source_message_id     :bigint
#  submitted_by_id       :bigint
#
# Indexes
#
#  index_ai_agent_learning_suggestions_on_account_id         (account_id)
#  index_ai_agent_learning_suggestions_on_ai_agent_id        (ai_agent_id)
#  index_ai_agent_learning_suggestions_on_conversation_id    (conversation_id)
#  index_ai_agent_learning_suggestions_on_reviewed_by_id     (reviewed_by_id)
#  index_ai_agent_learning_suggestions_on_source_message_id  (source_message_id)
#  index_ai_agent_learning_suggestions_on_submitted_by_id    (submitted_by_id)
#  index_ai_learning_suggestions_on_agent_and_message        (ai_agent_id,source_message_id) UNIQUE WHERE (source_message_id IS NOT NULL)
#  index_ai_learning_suggestions_on_agent_status_created     (ai_agent_id,status,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_agent_id => ai_agents.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => nullify
#  fk_rails_...  (reviewed_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (source_message_id => messages.id) ON DELETE => nullify
#  fk_rails_...  (submitted_by_id => users.id) ON DELETE => nullify
#
class AiAgentLearningSuggestion < ApplicationRecord
  TARGET_SECTIONS = %w[business_context tasks rules handoff additional].freeze

  enum status: {
    pending: 0,
    analyzing: 1,
    ready: 2,
    applied: 3,
    dismissed: 4,
    failed: 5,
    not_recommended: 6
  }

  belongs_to :account
  belongs_to :ai_agent
  belongs_to :conversation, optional: true
  belongs_to :source_message, class_name: 'Message', optional: true
  belongs_to :submitted_by, class_name: 'User', optional: true
  belongs_to :reviewed_by, class_name: 'User', optional: true

  validates :status, :customer_message, :human_answer, presence: true
  validates :customer_message, :human_answer, length: { maximum: 10_000 }
  validates :suggested_instruction, length: { maximum: 5_000 }
  validates :target_section, inclusion: { in: TARGET_SECTIONS }, allow_nil: true
  validate :review_content_present, if: -> { ready? || applied? }
  validate :records_belong_to_account
  validate :source_message_belongs_to_conversation

  scope :active_review, -> { where(status: [:pending, :analyzing, :ready, :failed]) }

  private

  def review_content_present
    errors.add(:suggested_instruction, "can't be blank") if suggested_instruction.blank?
    errors.add(:target_section, "can't be blank") if target_section.blank?
  end

  def records_belong_to_account
    linked_records = [ai_agent, conversation, source_message].compact
    return if account.blank? || linked_records.all? { |record| record.account_id == account_id }

    errors.add(:account, 'must own all linked records')
  end

  def source_message_belongs_to_conversation
    return if source_message.blank? || conversation.blank? || source_message.conversation_id == conversation_id

    errors.add(:source_message, 'must belong to conversation')
  end
end
