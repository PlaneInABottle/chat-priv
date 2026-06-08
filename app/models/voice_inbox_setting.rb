# == Schema Information
#
# Table name: voice_inbox_settings
#
#  id                  :bigint           not null, primary key
#  greeting            :text
#  instructions        :text
#  last_error          :text
#  livekit_room_prefix :string
#  recording_enabled   :boolean          default(FALSE), not null
#  settings            :jsonb            not null
#  status              :string           default("test_only"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  ai_agent_id         :bigint
#  fallback_team_id    :bigint
#  inbox_id            :bigint           not null
#
# Indexes
#
#  index_voice_inbox_settings_on_account_id               (account_id)
#  index_voice_inbox_settings_on_account_id_and_inbox_id  (account_id,inbox_id) UNIQUE
#  index_voice_inbox_settings_on_ai_agent_id              (ai_agent_id)
#  index_voice_inbox_settings_on_fallback_team_id         (fallback_team_id)
#  index_voice_inbox_settings_on_inbox_id                 (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (ai_agent_id => ai_agents.id)
#  fk_rails_...  (fallback_team_id => teams.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class VoiceInboxSetting < ApplicationRecord
  STATUSES = %w[test_only ready failed].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :ai_agent, optional: true
  belongs_to :fallback_team, class_name: 'Team', optional: true

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :inbox_id, uniqueness: { scope: :account_id }
  validates :greeting, length: { maximum: 20_000 }
  validates :instructions, length: { maximum: 20_000 }
  validate :associations_belong_to_account

  before_validation :set_defaults

  private

  def set_defaults
    self.livekit_room_prefix = "cw-voice-#{account_id}-#{inbox_id}" if livekit_room_prefix.blank? && account_id && inbox_id
  end

  def associations_belong_to_account
    errors.add(:inbox_id, 'must belong to account') if inbox && inbox.account_id != account_id
    errors.add(:ai_agent_id, 'must belong to account') if ai_agent && ai_agent.account_id != account_id
    errors.add(:fallback_team_id, 'must belong to account') if fallback_team && fallback_team.account_id != account_id
  end
end
