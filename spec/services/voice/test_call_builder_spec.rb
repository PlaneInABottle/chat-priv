require 'rails_helper'

RSpec.describe Voice::TestCallBuilder do
  describe '.perform!' do
    let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
    let(:api_channel) { create(:channel_api, account: account) }
    let(:inbox) { api_channel.inbox }
    let(:user) { create(:user, account: account) }
    let(:voice_agent) { create(:voice_agent, account: account) }

    before do
      create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent)
      allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return(
        {
          'status' => 'dispatched',
          'dispatch_id' => 'AD_test'
        }
      )
    end

    def expect_improvement_reservation(call, voice_agent, user)
      usage_event = call.account.ai_improvement_usage_events.find(call.meta['ai_improvement_usage_event_id'])
      expect(usage_event).to have_attributes(
        operation: 'voice_test',
        unit_type: 'audio_seconds',
        status: 'reserved',
        credits: 90,
        voice_agent_id: voice_agent.id,
        call_id: call.id,
        initiated_by_id: user.id
      )
    end

    it 'creates a LiveKit voice call in an API inbox', :aggregate_failures do
      voice_agent.update!(enabled: false)
      call = described_class.perform!(
        account: account,
        inbox: inbox,
        voice_agent: voice_agent,
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
      expect(call.meta['voice_agent_id']).to be_present
      expect(VoiceAgent.find(call.meta['voice_agent_id'])).to have_attributes(
        account_id: account.id,
        enabled: false
      )
      expect(call.contact).to be_nil
      expect(call.conversation).to be_nil
      expect(call.message).to be_nil
      expect(call.meta.dig('voice_agent_dispatch', 'status')).to eq('dispatched')
      expect(call.meta['ai_improvement_max_duration_seconds']).to eq(900)
      expect_improvement_reservation(call, voice_agent, user)
      expect(Voice::TestCallImprovementBudgetJob).to have_been_enqueued.with(call)
      payload = Voice::CallSerializer.new(call).payload
      expect(payload).to include(
        test_call: true,
        test_call_source: 'voice_ai_settings',
        test_call_initiated_by_user_id: user.id,
        test_duration_limit_seconds: 900
      )
      expect(payload).not_to have_key(:conversation_id)
      expect(payload).not_to have_key(:contact_id)
      expect(payload).not_to have_key(:message_id)
      expect(Voice::Livekit::AgentDispatchService).to have_received(:perform).with(
        call: call,
        metadata: hash_including(
          account_id: account.id,
          inbox_id: inbox.id,
          call_id: call.id,
          livekit_room_name: call.livekit_room_name,
          voice_agent_id: call.meta['voice_agent_id']
        )
      )
    end

    it 'rejects non API inboxes for MVP test calls' do
      web_inbox = create(:inbox, account: account)

      expect do
        described_class.perform!(account: account, inbox: web_inbox, voice_agent: voice_agent)
      end.to raise_error(ArgumentError, 'Voice MVP test calls require an API inbox')
    end

    it 'requires the selected inbox to be assigned to the selected voice agent' do
      other_agent = create(:voice_agent, account: account)

      expect do
        described_class.perform!(account: account, inbox: inbox, voice_agent: other_agent)
      end.to raise_error(ArgumentError, 'Assign this inbox to the selected voice agent before starting a test call.')
    end

    it 'rejects a selected voice agent from another account' do
      foreign_agent = create(:voice_agent)

      expect do
        described_class.perform!(account: account, inbox: inbox, voice_agent: foreign_agent)
      end.to raise_error(ArgumentError, 'Voice agent must belong to this account.')
    end

    it 'rejects test calls when account Voice AI access is disabled' do
      account.update!(voice_ai_enabled: false)

      expect do
        described_class.perform!(account: account, inbox: inbox, voice_agent: voice_agent)
      end.to raise_error(Voice::Usage::Admission::Error, 'Voice AI is disabled for this account.')
    end

    it 'rejects test calls when improvement credits are exhausted' do
      account.ai_improvement_settings = { monthly_credit_limit: 1 }
      account.save!
      limiter = AiImprovements::Usage::Limiter.new(account: account, operation: 'voice_test')
      limiter.consume!(limiter.reserve_or_raise!, unit_type: 'audio_seconds', units: 1)

      expect do
        described_class.perform!(account: account, inbox: inbox, voice_agent: voice_agent)
      end.to raise_error(AiImprovements::Usage::Exhausted)
      expect(Voice::Livekit::AgentDispatchService).not_to have_received(:perform)
    end

    it 'limits the test duration to currently available improvement credits' do
      account.ai_improvement_settings = { monthly_credit_limit: 3 }
      account.save!
      limiter = AiImprovements::Usage::Limiter.new(account: account, operation: 'text_test')
      limiter.consume!(limiter.reserve_or_raise!, unit_type: 'tokens', units: 1)

      call = described_class.perform!(account: account, inbox: inbox, voice_agent: voice_agent)
      usage_event = account.ai_improvement_usage_events.find(call.meta['ai_improvement_usage_event_id'])

      expect(usage_event).to have_attributes(status: 'reserved', credits: 2)
      expect(call.meta['ai_improvement_max_duration_seconds']).to eq(20)
    end

    it 'releases the improvement reservation when dispatch fails' do
      allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_raise('dispatch failed')
      allow(Voice::CallFinalizer).to receive(:perform!)

      expect do
        described_class.perform!(account: account, inbox: inbox, voice_agent: voice_agent)
      end.to raise_error('dispatch failed')

      expect(account.ai_improvement_usage_events.last).to be_released
      expect(Voice::CallFinalizer).to have_received(:perform!).with(
        call: account.calls.last,
        status: 'failed',
        end_reason: 'test_call_start_failed'
      )
    end
  end
end
