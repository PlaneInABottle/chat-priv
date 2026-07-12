# frozen_string_literal: true

# == Schema Information
#
# Table name: ai_knowledge_source_assignments
#
#  id                     :bigint           not null, primary key
#  assistant_type         :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  ai_knowledge_source_id :bigint           not null
#  assistant_id           :bigint           not null
#
# Indexes
#
#  idx_on_ai_knowledge_source_id_1c19131e3a                 (ai_knowledge_source_id)
#  index_ai_knowledge_assignments_on_account_and_assistant  (account_id,assistant_type,assistant_id)
#  index_ai_knowledge_assignments_on_assistant_and_source   (assistant_type,assistant_id,ai_knowledge_source_id) UNIQUE
#  index_ai_knowledge_source_assignments_on_account_id      (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_knowledge_source_id => ai_knowledge_sources.id) ON DELETE => cascade
#
class AiKnowledgeSourceAssignment < ApplicationRecord
  ASSISTANT_TYPES = %w[AiAgent VoiceAgent].freeze

  belongs_to :account
  belongs_to :ai_knowledge_source
  belongs_to :assistant, polymorphic: true

  validates :assistant_type, inclusion: { in: ASSISTANT_TYPES }
  validates :ai_knowledge_source_id, uniqueness: { scope: [:assistant_type, :assistant_id] }
  validate :records_belong_to_account

  before_validation :set_account_from_assistant

  private

  def set_account_from_assistant
    self.account ||= assistant&.account
  end

  def records_belong_to_account
    return if account.blank? || ai_knowledge_source.blank? || assistant.blank?
    return if ai_knowledge_source.account_id == account_id && assistant.account_id == account_id

    errors.add(:account, 'must own the source and assistant')
  end
end
