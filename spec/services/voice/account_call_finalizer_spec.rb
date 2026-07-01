require 'rails_helper'

RSpec.describe Voice::AccountCallFinalizer do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:other_account) { create(:account, settings: { voice_ai_enabled: true }) }

  before do
    allow(Voice::CallFinalizer).to receive(:perform!)
    allow(Rails.logger).to receive(:warn)
  end

  it 'finalizes only active LiveKit calls for the account' do
    active_call = create_livekit_call(account: account, status: 'in_progress')
    ringing_call = create_livekit_call(account: account, status: 'ringing')
    create_livekit_call(account: account, status: 'completed')
    create(:call, account: account, provider: :twilio, status: 'in_progress')
    create_livekit_call(account: other_account, status: 'in_progress')

    described_class.perform(account: account)

    expect(Voice::CallFinalizer).to have_received(:perform!).with(
      call: active_call,
      status: 'completed',
      end_reason: 'voice_ai_disabled'
    )
    expect(Voice::CallFinalizer).to have_received(:perform!).with(
      call: ringing_call,
      status: 'completed',
      end_reason: 'voice_ai_disabled'
    )
    expect(Voice::CallFinalizer).to have_received(:perform!).twice
  end

  it 'continues finalizing later calls when one call fails' do
    failing_call = create_livekit_call(account: account, provider_call_id: 'failing-room')
    succeeding_call = create_livekit_call(account: account, provider_call_id: 'succeeding-room')

    allow(Voice::CallFinalizer).to receive(:perform!).with(
      call: failing_call,
      status: 'completed',
      end_reason: 'voice_ai_disabled'
    ).and_raise(StandardError, 'livekit timeout')

    described_class.perform(account: account)

    expect(Voice::CallFinalizer).to have_received(:perform!).with(
      call: succeeding_call,
      status: 'completed',
      end_reason: 'voice_ai_disabled'
    )
    expect(Rails.logger).to have_received(:warn).with(
      /voice call finalization failed account_id=#{account.id} call_id=#{failing_call.id} error=StandardError: livekit timeout/
    )
  end

  def create_livekit_call(account:, status: 'in_progress', provider_call_id: SecureRandom.hex(8))
    conversation = create(:conversation, account: account)
    create(
      :call,
      account: account,
      conversation: conversation,
      inbox: conversation.inbox,
      contact: conversation.contact,
      provider: :livekit,
      status: status,
      started_at: Time.zone.now,
      provider_call_id: provider_call_id,
      meta: { 'livekit_room_name' => provider_call_id }
    )
  end
end
