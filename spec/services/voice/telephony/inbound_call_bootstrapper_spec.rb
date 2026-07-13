require 'rails_helper'

RSpec.describe Voice::Telephony::InboundCallBootstrapper do
  describe '.perform!' do
    let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
    let(:inbox) { create(:channel_api, account: account).inbox }
    let(:voice_agent) { create(:voice_agent, account: account, enabled: true) }
    let!(:setting) { create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent) }
    let!(:provider_connection) { create(:voice_provider_connection, account: account, provider: 'test_sip') }
    let!(:voice_number) do
      create(
        :voice_number,
        account: account,
        voice_provider_connection: provider_connection,
        voice_inbox_setting: setting,
        livekit_inbound_trunk_id: 'trunk-1',
        livekit_dispatch_rule_id: 'rule-1'
      )
    end

    before do
      allow(Voice::Recordings::StartService).to receive(:perform)
    end

    it 'creates an in-progress LiveKit call from a dialed voice number' do
      call = described_class.perform!(
        provider_call_id: 'sip-room-1',
        metadata: {
          account_id: account.id,
          from_number: '+905551112233',
          to_number: voice_number.phone_number,
          contact_name: 'SIP Caller'
        }
      )

      expect(call).to have_attributes(
        account_id: account.id,
        inbox_id: inbox.id,
        provider: 'livekit',
        provider_call_id: 'sip-room-1',
        status: 'in_progress'
      )
      expect(call.meta).to include(
        'livekit_room_name' => 'sip-room-1',
        'voice_number_id' => voice_number.id,
        'voice_provider_connection_id' => provider_connection.id,
        'voice_inbox_setting_id' => setting.id,
        'voice_agent_id' => voice_agent.id,
        'to_number' => voice_number.phone_number
      )
      expect(call.conversation).to be_present
      expect(call.message).to be_present
      expect(Voice::Recordings::StartService).to have_received(:perform).with(call: call)
    end

    it 'resolves by explicit voice number id and ignores a conflicting account id' do
      foreign_account = create(:account, settings: { voice_ai_enabled: true })

      expect do
        described_class.perform!(
          provider_call_id: 'sip-room-foreign',
          metadata: { voice_number_id: voice_number.id, account_id: foreign_account.id }
        )
      end.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'resolves by LiveKit trunk and dispatch identifiers' do
      call = described_class.perform!(
        provider_call_id: 'sip-room-trunk',
        metadata: {
          account_id: account.id,
          from_number: '+905551112233',
          livekit_inbound_trunk_id: 'trunk-1',
          livekit_dispatch_rule_id: 'rule-1'
        }
      )

      expect(call.meta['voice_number_id']).to eq(voice_number.id)
      expect(call.meta['voice_inbox_setting_id']).to eq(setting.id)
    end

    it 'uses a phone-like token from the LiveKit room name when caller metadata is missing' do
      call = described_class.perform!(
        provider_call_id: 'local-sip-_+905551112233_abc123',
        metadata: { account_id: account.id, voice_number_id: voice_number.id }
      )

      expect(call.from_number).to eq('+905551112233')
      expect(call.contact.phone_number).to eq('+905551112233')
    end

    it 'returns an existing call instead of creating a duplicate' do
      existing = described_class.perform!(provider_call_id: 'sip-room-existing', metadata: { account_id: account.id, voice_number_id: voice_number.id })

      expect do
        result = described_class.perform!(provider_call_id: 'sip-room-existing', metadata: { account_id: account.id, voice_number_id: voice_number.id })
        expect(result).to eq(existing)
      end.not_to change(Call, :count)
    end

    it 'does not create a new production call for a paused assistant' do
      voice_agent.update!(enabled: false)

      expect do
        described_class.perform!(
          provider_call_id: 'sip-room-paused',
          metadata: { account_id: account.id, voice_number_id: voice_number.id }
        )
      end.to raise_error(ActiveRecord::RecordNotFound, 'Voice assistant is paused')

      expect(Call.find_by(provider_call_id: 'sip-room-paused')).to be_nil
    end

    it 'does not resolve an explicit voice number without an account scope' do
      expect do
        described_class.perform!(
          provider_call_id: 'sip-room-unscoped-number',
          metadata: { voice_number_id: voice_number.id }
        )
      end.to raise_error(ActiveRecord::RecordNotFound, 'Voice number or voice inbox setting not configured')
    end

    it 'raises not found when no voice number or scoped setting can be resolved' do
      expect do
        described_class.perform!(
          provider_call_id: 'sip-room-missing-routing',
          metadata: { to_number: '+908509999999' }
        )
      end.to raise_error(ActiveRecord::RecordNotFound, 'Voice number or voice inbox setting not configured')
    end

    it 'does not resolve an explicit voice inbox setting without an account scope' do
      expect do
        described_class.perform!(
          provider_call_id: 'sip-room-unscoped-setting',
          metadata: { voice_inbox_setting_id: setting.id }
        )
      end.to raise_error(ActiveRecord::RecordNotFound, 'Voice number or voice inbox setting not configured')
    end
  end
end
