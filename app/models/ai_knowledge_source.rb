# frozen_string_literal: true

# == Schema Information
#
# Table name: ai_knowledge_sources
#
#  id          :bigint           not null, primary key
#  content     :text             not null
#  name        :string           not null
#  source_type :string           default("manual"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_ai_knowledge_sources_on_account_id           (account_id)
#  index_ai_knowledge_sources_on_account_id_and_name  (account_id,name)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class AiKnowledgeSource < ApplicationRecord
  SOURCE_TYPES = %w[manual].freeze
  MAX_CONTENT_LENGTH = 100_000

  belongs_to :account
  has_many :assignments, class_name: 'AiKnowledgeSourceAssignment', dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
  validates :content, presence: true, length: { maximum: MAX_CONTENT_LENGTH }

  before_validation :normalize_text

  private

  def normalize_text
    self.name = name.to_s.strip
    self.content = content.to_s.strip
  end
end
