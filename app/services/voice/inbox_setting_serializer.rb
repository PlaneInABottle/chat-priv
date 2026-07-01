# frozen_string_literal: true

class Voice::InboxSettingSerializer
  def initialize(setting)
    @setting = setting
  end

  def payload
    {
      id: setting.id,
      account_id: setting.account_id,
      inbox_id: setting.inbox_id,
      inbox_name: setting.inbox.name,
      inbox_channel_type: setting.inbox.channel_type,
      voice_agent_id: setting.voice_agent_id,
      fallback_team_id: setting.fallback_team_id,
      livekit_room_prefix: setting.livekit_room_prefix,
      recording_enabled: setting.recording_enabled,
      last_error: setting.last_error,
      settings: setting.settings
    }
  end

  private

  attr_reader :setting
end
