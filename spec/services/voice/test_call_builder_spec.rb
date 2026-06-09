require 'rails_helper'

RSpec.describe Voice::TestCallBuilder do
  describe '.perform!' do
    let(:account) { create(:account) }
    let(:api_channel) { create(:channel_api, account: account) }
    let(:inbox) { api_channel.inbox }
    let(:user) { create(:user, account: account) }

    before do
      allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return(
        {
          'status' => 'dispatched',
          'dispatch_id' => 'AD_test'
        }
      )
    end

    it 'creates a LiveKit voice call in an API inbox' do
      call = described_class.perform!(
        account: account,
        inbox: inbox,
        caller_name: 'Test Caller',
        caller_number: '+905551112233',
        initiated_by: user
      )

      expect(call).to be_livekit
      expect(call.status).to eq('in_progress')
      expect(call.livekit_room_name).to be_present
      expect(call).to be_test_call
      expect(call.test_call_source).to eq('voice_ai_settings')
      expect(call.test_call_initiated_by_user_id).to eq(user.id)
      expect(call.meta['voice_greeting']).to be_present
      expect(call.meta['voice_instructions']).to include('Istanbul Turkcesi')
      expect(call.contact).to be_nil
      expect(call.conversation).to be_nil
      expect(call.message).to be_nil
      expect(call.meta.dig('voice_agent_dispatch', 'status')).to eq('dispatched')
      expect(Voice::CallSerializer.new(call).payload).to include(
        test_call: true,
        test_call_source: 'voice_ai_settings',
        test_call_initiated_by_user_id: user.id,
        conversation_id: nil,
        contact_id: nil,
        message_id: nil
      )
      expect(Voice::Livekit::AgentDispatchService).to have_received(:perform).with(
        call: call,
        metadata: hash_including(
          account_id: account.id,
          inbox_id: inbox.id,
          call_id: call.id,
          livekit_room_name: call.livekit_room_name,
          voice_greeting: call.meta['voice_greeting'],
          voice_instructions: call.meta['voice_instructions']
        )
      )
    end

    it 'rejects non API inboxes for MVP test calls' do
      web_inbox = create(:inbox, account: account)

      expect do
        described_class.perform!(account: account, inbox: web_inbox)
      end.to raise_error(ArgumentError, 'Voice MVP test calls require an API inbox')
    end
  end
end
