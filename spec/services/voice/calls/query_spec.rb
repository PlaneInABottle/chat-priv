require 'rails_helper'

RSpec.describe Voice::Calls::Query do
  let(:account) { create(:account) }
  let(:first_inbox) { create(:inbox, account: account) }
  let(:second_inbox) { create(:inbox, account: account) }
  let(:voice_agent) { create(:voice_agent, account: account) }
  let(:release) { create(:voice_agent_release, account: account, voice_agent: voice_agent) }

  it 'returns only authorized real Voice AI calls and applies owner-facing filters' do
    matching_call = create_call(
      inbox: first_inbox,
      status: 'completed',
      phone: '+905551112233',
      handoff_status: 'accepted'
    )
    create_call(inbox: second_inbox, status: 'completed', phone: '+905559999999')
    create_call(inbox: first_inbox, status: 'failed', phone: '+905551112233')
    create_call(inbox: first_inbox, status: 'completed', phone: '+905551112233', test_call: true)
    create(:call, account: account, inbox: first_inbox)

    results = described_class.new(
      account: account,
      inbox_ids: [first_inbox.id],
      params: {
        status: 'completed',
        handoff_status: 'accepted',
        voice_agent_id: voice_agent.id,
        phone: '555111'
      }
    ).results

    expect(results).to contain_exactly(matching_call)
  end

  def create_call(inbox:, status:, phone:, handoff_status: 'none', test_call: false)
    conversation = create(:conversation, account: account, inbox: inbox)
    create(
      :call,
      account: account,
      inbox: inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :livekit,
      status: status,
      voice_agent_release: release,
      meta: {
        'from_number' => phone,
        'handoff_status' => handoff_status,
        'voice_agent_id' => voice_agent.id,
        'test_call' => test_call
      }
    )
  end
end
