# == Schema Information
#
# Table name: voice_inbox_settings
#
#  id                  :bigint           not null, primary key
#  last_error          :text
#  livekit_room_prefix :string
#  recording_enabled   :boolean          default(FALSE), not null
#  settings            :jsonb            not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  fallback_team_id    :bigint
#  inbox_id            :bigint           not null
#  voice_agent_id      :bigint
#
# Indexes
#
#  index_voice_inbox_settings_on_account_id               (account_id)
#  index_voice_inbox_settings_on_account_id_and_inbox_id  (account_id,inbox_id) UNIQUE
#  index_voice_inbox_settings_on_fallback_team_id         (fallback_team_id)
#  index_voice_inbox_settings_on_inbox_id                 (inbox_id)
#  index_voice_inbox_settings_on_voice_agent_id           (voice_agent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (fallback_team_id => teams.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (voice_agent_id => voice_agents.id)
#
class VoiceInboxSetting < ApplicationRecord
  belongs_to :account
  belongs_to :inbox
  belongs_to :voice_agent, optional: true
  belongs_to :fallback_team, class_name: 'Team', optional: true
  has_many :voice_numbers, dependent: :destroy

  validates :inbox_id, uniqueness: { scope: :account_id }
  validate :associations_belong_to_account

  before_validation :set_defaults

  private

  def set_defaults
    self.livekit_room_prefix = "kozmopath-voice-#{account_id}-#{inbox_id}" if livekit_room_prefix.blank? && account_id && inbox_id
  end

  def associations_belong_to_account
    errors.add(:inbox_id, 'must belong to account') if inbox && inbox.account_id != account_id
    errors.add(:voice_agent_id, 'must belong to account') if voice_agent && voice_agent.account_id != account_id
    errors.add(:fallback_team_id, 'must belong to account') if fallback_team && fallback_team.account_id != account_id
  end
end
