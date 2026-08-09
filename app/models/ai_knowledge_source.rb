# frozen_string_literal: true

# == Schema Information
#
# Table name: ai_knowledge_sources
#
#  id                   :bigint           not null, primary key
#  content              :text             not null
#  last_sync_started_at :datetime
#  last_synced_at       :datetime
#  name                 :string           not null
#  source_type          :string           default("manual"), not null
#  source_urls          :jsonb            not null
#  sync_error           :text
#  sync_status          :integer          default("not_applicable"), not null
#  website_url          :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#
# Indexes
#
#  idx_ai_knowledge_sources_on_website_sync_schedule         (source_type,sync_status,last_synced_at)
#  index_ai_knowledge_sources_on_account_id                  (account_id)
#  index_ai_knowledge_sources_on_account_id_and_name         (account_id,name)
#  index_ai_knowledge_sources_on_account_id_and_source_type  (account_id,source_type)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#
class AiKnowledgeSource < ApplicationRecord
  SOURCE_TYPES = %w[manual website].freeze
  MAX_CONTENT_LENGTH = 100_000

  enum :sync_status, { not_applicable: 0, pending: 1, syncing: 2, ready: 3, failed: 4 }, prefix: :sync

  belongs_to :account
  has_many :assignments, class_name: 'AiKnowledgeSourceAssignment', dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validates :source_type, presence: true, inclusion: { in: SOURCE_TYPES }
  validates :content, presence: true, if: :manual?
  validates :content, length: { maximum: MAX_CONTENT_LENGTH }, allow_blank: true
  validates :website_url, presence: true, if: :website?

  before_validation :normalize_attributes

  def manual?
    source_type == 'manual'
  end

  def website?
    source_type == 'website'
  end

  def available?
    content.present?
  end

  private

  def normalize_attributes
    self.name = name.to_s.strip
    self.content = content.to_s.strip
    normalize_source_type_attributes
  end

  def normalize_source_type_attributes
    if website?
      self.website_url = AiAgents::WebsiteCrawler.normalize_url(website_url) if website_url.present?
      self.sync_status = :pending if new_record? && sync_not_applicable?
    else
      self.website_url = nil
      self.source_urls = []
      self.sync_status = :not_applicable
      self.sync_error = nil
    end
  rescue AiAgents::WebsiteCrawler::InvalidWebsite => e
    errors.add(:website_url, e.message)
  end
end
