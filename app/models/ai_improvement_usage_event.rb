# frozen_string_literal: true

# == Schema Information
#
# Table name: ai_improvement_usage_events
#
#  id              :bigint           not null, primary key
#  credits         :integer          default(1), not null
#  idempotency_key :string           not null
#  metadata        :jsonb            not null
#  operation       :string           not null
#  period_end_at   :datetime         not null
#  period_start_at :datetime         not null
#  status          :integer          default("reserved"), not null
#  unit_type       :string           not null
#  units           :bigint           default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  ai_agent_id     :bigint
#  call_id         :bigint
#  initiated_by_id :bigint
#  voice_agent_id  :bigint
#
# Indexes
#
#  idx_ai_improvement_usage_on_account_operation         (account_id,operation,created_at)
#  idx_ai_improvement_usage_on_account_period_status     (account_id,period_start_at,status)
#  idx_ai_improvement_usage_on_idempotency               (account_id,period_start_at,idempotency_key) UNIQUE
#  index_ai_improvement_usage_events_on_account_id       (account_id)
#  index_ai_improvement_usage_events_on_ai_agent_id      (ai_agent_id)
#  index_ai_improvement_usage_events_on_call_id          (call_id)
#  index_ai_improvement_usage_events_on_initiated_by_id  (initiated_by_id)
#  index_ai_improvement_usage_events_on_voice_agent_id   (voice_agent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (ai_agent_id => ai_agents.id) ON DELETE => nullify
#  fk_rails_...  (call_id => calls.id) ON DELETE => nullify
#  fk_rails_...  (initiated_by_id => users.id) ON DELETE => nullify
#  fk_rails_...  (voice_agent_id => voice_agents.id) ON DELETE => nullify
#
class AiImprovementUsageEvent < ApplicationRecord
  OPERATIONS = %w[text_test evaluation website_import learning knowledge_indexing voice_test].freeze
  UNIT_TYPES = %w[tokens embedding_tokens audio_seconds].freeze

  enum status: { reserved: 0, consumed: 1, released: 2 }

  belongs_to :account
  belongs_to :ai_agent, optional: true
  belongs_to :voice_agent, optional: true
  belongs_to :call, optional: true
  belongs_to :initiated_by, class_name: 'User', optional: true

  validates :operation, inclusion: { in: OPERATIONS }
  validates :unit_type, inclusion: { in: UNIT_TYPES }
  validates :units, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :credits, numericality: { only_integer: true, greater_than: 0 }
  validates :period_start_at, :period_end_at, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: { scope: [:account_id, :period_start_at] }
  validate :associated_records_belong_to_account

  scope :active, -> { where(status: %i[reserved consumed]) }
  scope :for_period, ->(period_start_at) { where(period_start_at: period_start_at) }

  private

  def associated_records_belong_to_account
    validate_account_owner(ai_agent, :ai_agent)
    validate_account_owner(voice_agent, :voice_agent)
    validate_account_owner(call, :call)
  end

  def validate_account_owner(record, attribute)
    return if record.blank? || account.blank? || record.account_id == account_id

    errors.add(attribute, 'must belong to account')
  end
end
