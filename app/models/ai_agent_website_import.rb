# == Schema Information
#
# Table name: ai_agent_website_imports
#
#  id                     :bigint           not null, primary key
#  applied_at             :datetime
#  base_draft_fingerprint :string           not null
#  completed_at           :datetime
#  error_code             :string
#  error_message          :text
#  mode                   :integer          default("initial"), not null
#  proposed_sections      :jsonb            not null
#  source_urls            :jsonb            not null
#  stage                  :integer          default("queued"), not null
#  started_at             :datetime
#  status                 :integer          default("pending"), not null
#  website_url            :string           not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  ai_agent_id            :bigint           not null
#  requested_by_id        :bigint
#
# Indexes
#
#  index_ai_agent_website_imports_on_account_id       (account_id)
#  index_ai_agent_website_imports_on_ai_agent_id      (ai_agent_id)
#  index_ai_agent_website_imports_on_requested_by_id  (requested_by_id)
#  index_ai_website_imports_on_active_agent           (ai_agent_id) UNIQUE WHERE (status = ANY (ARRAY[0, 1]))
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_agent_id => ai_agents.id) ON DELETE => cascade
#  fk_rails_...  (requested_by_id => users.id) ON DELETE => nullify
#
class AiAgentWebsiteImport < ApplicationRecord
  PROCESSING_TIMEOUT = 5.minutes
  MODES = { initial: 0, preview: 1 }.freeze
  STATUSES = { pending: 0, running: 1, ready: 2, applied: 3, failed: 4, dismissed: 5 }.freeze
  STAGES = { queued: 0, crawling: 1, generating: 2, applying: 3, complete: 4 }.freeze
  APPLYABLE_SECTIONS = %w[identity business_context tasks rules].freeze

  belongs_to :account
  belongs_to :ai_agent
  belongs_to :requested_by, class_name: 'User', optional: true

  enum :mode, MODES, prefix: true
  enum :status, STATUSES
  enum :stage, STAGES, prefix: true

  validates :website_url, presence: true, length: { maximum: 2048 }
  validates :base_draft_fingerprint, presence: true
  validate :ai_agent_belongs_to_account
  validate :requested_by_belongs_to_account

  scope :latest_first, -> { order(created_at: :desc, id: :desc) }

  def active?
    pending? || running?
  end

  def stale?
    active? && updated_at < PROCESSING_TIMEOUT.ago
  end

  def customer_error_code
    return if error_code.blank?
    return 'timed_out' if error_code == 'stale_import'
    return 'ai_improvement_credits_exhausted' if error_code == 'AiImprovements::Usage::Exhausted'
    return 'website_too_large' if error_code == 'SafeFetch::FileTooLargeError'
    return 'website_unreachable' if error_code.start_with?('SafeFetch::')
    return 'generation_failed' if error_code.start_with?('AiAgents::WebsiteInstructionGenerator::')

    'analysis_failed'
  end

  private

  def ai_agent_belongs_to_account
    return if ai_agent.blank? || account.blank? || ai_agent.account_id == account_id

    errors.add(:ai_agent, 'must belong to account')
  end

  def requested_by_belongs_to_account
    return if requested_by.blank? || account.blank? || requested_by.accounts.exists?(id: account_id)

    errors.add(:requested_by, 'must belong to account')
  end
end
