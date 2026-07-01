require 'rails_helper'

RSpec.describe Voice::InboundCallBuilder do
  describe '.perform!' do
    it 'ignores a voice_inbox_setting_id from another account when selecting the voice agent' do
      account = create(:account, settings: { voice_ai_enabled: true })
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
      expect(call.meta['voice_inbox_setting_id']).to eq(VoiceInboxSetting.find_by!(account: account, inbox: inbox).id)
    end

    it 'does not fall back to an arbitrary voice agent without an inbox assignment' do
      account = create(:account, settings: { voice_ai_enabled: true })
      inbox = create(:channel_api, account: account).inbox
      create(:voice_agent, account: account, enabled: true)
      foreign_setting = create(:voice_inbox_setting)

      call = described_class.perform!(
        inbox: inbox,
        from_number: '+905551112233',
        call_sid: 'livekit-room-unassigned',
        provider: :livekit,
        extra_meta: {
          'livekit_room_name' => 'livekit-room-unassigned',
          'voice_inbox_setting_id' => foreign_setting.id,
          'voice_agent_id' => foreign_setting.voice_agent_id
        }
      )

      expect(call.meta).not_to have_key('voice_agent_id')
      expect(call.meta).not_to have_key('voice_inbox_setting_id')
    end

    it 'rejects new real LiveKit calls when account Voice AI access is disabled' do
      account = create(:account, settings: { voice_ai_enabled: false })
      inbox = create(:channel_api, account: account).inbox

      expect do
        described_class.perform!(
          inbox: inbox,
          from_number: '+905551112233',
          call_sid: 'livekit-room-disabled',
          provider: :livekit,
          extra_meta: { 'livekit_room_name' => 'livekit-room-disabled' }
        )
      end.to raise_error(Voice::Usage::Admission::Error, 'Voice AI is disabled for this account.')
    end

    it 'checks admission while holding the account lock for real LiveKit calls' do
      account = create(:account, settings: { voice_ai_enabled: true })
      inbox = create(:channel_api, account: account).inbox
      allow(inbox).to receive(:account).and_return(account)
      expect(account).to receive(:with_lock).and_call_original

      described_class.perform!(
        inbox: inbox,
        from_number: '+905551112233',
        call_sid: 'livekit-room-locked',
        provider: :livekit,
        extra_meta: { 'livekit_room_name' => 'livekit-room-locked' }
      )
    end

    it 'reuses an existing contact with the same phone number for LiveKit calls' do
      account = create(:account, settings: { voice_ai_enabled: true })
      inbox = create(:channel_api, account: account).inbox
      contact = create(:contact, account: account, phone_number: '+905551112233')

      call = described_class.perform!(
        inbox: inbox,
        from_number: '+905551112233',
        call_sid: 'livekit-room-existing-contact',
        provider: :livekit,
        extra_meta: { 'livekit_room_name' => 'livekit-room-existing-contact' }
      )

      expect(call.contact).to eq(contact)
      expect(account.contacts.where(phone_number: '+905551112233').count).to eq(1)
    end
  end
end
