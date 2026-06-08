# == Schema Information
#
# Table name: call_transcript_segments
#
#  id                  :bigint           not null, primary key
#  confidence          :float
#  ended_at            :datetime
#  metadata            :jsonb            not null
#  role                :string           not null
#  source              :string           default("livekit_agent"), not null
#  started_at          :datetime
#  text                :text             not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  call_id             :bigint           not null
#  conversation_id     :bigint           not null
#  external_segment_id :string
#
# Indexes
#
#  idx_call_segments_on_account_conversation          (account_id,conversation_id)
#  idx_call_segments_on_call_created                  (call_id,created_at)
#  idx_call_segments_on_call_external_id              (call_id,external_segment_id) UNIQUE WHERE (external_segment_id IS NOT NULL)
#  index_call_transcript_segments_on_account_id       (account_id)
#  index_call_transcript_segments_on_call_id          (call_id)
#  index_call_transcript_segments_on_conversation_id  (conversation_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (call_id => calls.id)
#  fk_rails_...  (conversation_id => conversations.id)
#
class CallTranscriptSegment < ApplicationRecord
  ROLES = %w[caller ai agent system].freeze
  SOURCES = %w[livekit_agent browser_agent sip post_call simulator].freeze

  belongs_to :account
  belongs_to :call
  belongs_to :conversation

  validates :role, presence: true, inclusion: { in: ROLES }
  validates :source, presence: true, inclusion: { in: SOURCES }
  validates :text, presence: true, length: { maximum: 20_000 }
  validates :external_segment_id, uniqueness: { scope: :call_id }, allow_blank: true
  validate :account_scope_matches_call

  private

  def account_scope_matches_call
    return unless call

    errors.add(:account_id, 'must match call') if account_id != call.account_id
    errors.add(:conversation_id, 'must match call') if conversation_id != call.conversation_id
  end
end
