# == Schema Information
#
# Table name: voice_tool_events
#
#  id            :bigint           not null, primary key
#  arguments     :jsonb            not null
#  duration_ms   :integer
#  error_message :text
#  result        :jsonb            not null
#  source        :string           default("livekit_agent"), not null
#  status        :string           default("executed"), not null
#  tool          :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  call_id       :bigint           not null
#  external_id   :string
#
# Indexes
#
#  idx_voice_tool_events_on_account_tool      (account_id,tool)
#  idx_voice_tool_events_on_call_created      (call_id,created_at)
#  idx_voice_tool_events_on_call_external_id  (call_id,external_id) UNIQUE WHERE (external_id IS NOT NULL)
#  index_voice_tool_events_on_account_id      (account_id)
#  index_voice_tool_events_on_call_id         (call_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (call_id => calls.id)
#
class VoiceToolEvent < ApplicationRecord
  STATUSES = %w[started executed error rejected].freeze
  SOURCES = %w[livekit_agent browser_agent sip post_call simulator].freeze

  belongs_to :account
  belongs_to :call

  validates :tool, presence: true, length: { maximum: 120 }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :error_message, length: { maximum: 2000 }
  validates :external_id, uniqueness: { scope: :call_id }, allow_blank: true
  validate :account_scope_matches_call

  private

  def account_scope_matches_call
    return unless call

    errors.add(:account_id, 'must match call') if account_id != call.account_id
  end
end
