require 'rails_helper'

RSpec.describe Voice::Recordings::Query do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:other_inbox) { create(:channel_api, account: account).inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+905551112233') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      contact: contact,
      conversation: conversation,
      provider: :livekit,
      status: 'completed',
      meta: { 'handoff_status' => 'accepted' }
    )
  end
  let!(:recording) do
    create(
      :voice_recording,
      call: call,
      status: 'completed',
      created_at: 2.days.ago
    )
  end
  let!(:other_recording) do
    other_conversation = create(:conversation, account: account, inbox: other_inbox)
    other_call = create(
      :call,
      account: account,
      inbox: other_inbox,
      contact: other_conversation.contact,
      conversation: other_conversation,
      provider: :livekit,
      status: 'in_progress'
    )
    create(:voice_recording, call: other_call, status: 'active')
  end

  it 'filters by allowed inbox ids before applying other filters' do
    results = described_class.new(account: account, params: {}, inbox_ids: [inbox.id]).results

    expect(results).to contain_exactly(recording)
  end

  it 'filters by status, call status, handoff status, contact, and inbox' do
    results = described_class.new(
      account: account,
      params: {
        status: 'completed',
        call_status: 'completed',
        handoff_status: 'accepted',
        contact_id: contact.id,
        inbox_id: inbox.id
      }
    ).results

    expect(results).to contain_exactly(recording)
  end

  it 'escapes phone search wildcards' do
    results = described_class.new(account: account, params: { phone: '%_' }).results

    expect(results).to be_empty
  end

  it 'filters by created date range' do
    results = described_class.new(
      account: account,
      params: {
        from: 3.days.ago.iso8601,
        to: 1.day.ago.iso8601
      }
    ).results

    expect(results).to contain_exactly(recording)
  end
end
