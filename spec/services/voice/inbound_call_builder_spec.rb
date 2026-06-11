require 'rails_helper'

RSpec.describe Voice::InboundCallBuilder do
  describe '.perform!' do
    it 'ignores a voice_inbox_setting_id from another account when selecting the voice agent' do
      account = create(:account)
      api_channel = create(:channel_api, account: account)
      inbox = api_channel.inbox
      local_voice_agent = account.voice_agents.first
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: local_voice_agent)
      foreign_setting = create(:voice_inbox_setting)

      call = described_class.perform!(
        inbox: inbox,
        from_number: '+905551112233',
        call_sid: 'livekit-room-1',
        provider: :livekit,
        extra_meta: {
          'livekit_room_name' => 'livekit-room-1',
          'voice_inbox_setting_id' => foreign_setting.id
        }
      )

      expect(call.meta['voice_agent_id']).to eq(local_voice_agent.id)
    end
  end
end
