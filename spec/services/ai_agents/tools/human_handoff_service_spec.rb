require 'rails_helper'

RSpec.describe AiAgents::Tools::HumanHandoffService do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:trigger_message) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact)
  end
  let!(:vip_label) { create(:label, account: account, title: 'vip') }
  let!(:billing_label) { create(:label, account: account, title: 'billing') }
  let(:service) do
    described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :test,
      conversation: conversation,
      trigger_message: trigger_message,
      settings: {
        'allowed_labels' => %w[vip ai_handoff]
      }
    )
  end

  it 'returns preview payload with filtered labels and terminal action' do
    result = service.call(args: {
      'reason' => 'Billing issue',
      'customer_message' => 'I am transferring you to a human agent.',
      'internal_note' => 'Customer needs finance review',
      'labels' => %w[vip ignored]
    })

    expect(result[:terminal_action]).to eq('handoff')
    expect(result[:conversation_status]).to eq('open')
    expect(result[:private_note_preview]).to include(
      'AI handoff brief',
      "Reason\nBilling issue",
      "Latest customer message\nIncoming Message",
      "Context for the team\nCustomer needs finance review",
      "Labels\nvip"
    )
    expect(result[:customer_message]).to eq('I am transferring you to a human agent.')
    expect(result[:labels_requested]).to eq(%w[vip ignored])
    expect(result[:labels_to_apply]).to eq(['vip'])
    expect(result[:labels_ignored]).to eq(['ignored'])
  end

  it 'drops labels that do not exist in the account even when allowed' do
    result = service.call(args: {
      'reason' => 'Escalation',
      'customer_message' => 'A teammate will continue from here.',
      'internal_note' => 'Need a person',
      'labels' => ['ai_handoff', 'billing']
    })

    expect(result[:labels_to_apply]).to eq([])
    expect(result[:labels_ignored]).to match_array(%w[ai_handoff billing])
  end

  it 'keeps existing account labels when no allowed subset is configured' do
    unrestricted_service = described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :test,
      settings: {}
    )

    result = unrestricted_service.call(args: {
      'reason' => 'Escalation',
      'customer_message' => 'I am handing this over to a teammate.',
      'internal_note' => 'Need billing help',
      'labels' => ['billing', 'missing']
    })

    expect(result[:labels_to_apply]).to eq(['billing'])
    expect(result[:labels_ignored]).to eq(['missing'])
  end

  it 'matches labels case-insensitively' do
    result = service.call(args: {
      'reason' => 'Escalation',
      'customer_message' => 'A VIP specialist will join shortly.',
      'internal_note' => 'Need VIP handling',
      'labels' => ['VIP', 'Billing', 'Missing']
    })

    expect(result[:labels_requested]).to eq(%w[vip billing missing])
    expect(result[:labels_to_apply]).to eq(['vip'])
    expect(result[:labels_ignored]).to eq(%w[billing missing])
  end

  it 'executes live handoff side effects in live mode only' do
    live_service = described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      settings: {
        'allowed_labels' => %w[vip billing]
      }
    )

    expect do
      @result = live_service.call(args: {
        'reason' => 'Billing issue',
        'customer_message' => 'I am transferring you to a billing specialist.',
        'internal_note' => 'Customer needs finance review',
        'labels' => %w[VIP missing]
      })
    end.to change { conversation.reload.messages.count }.by(2)

    conversation.reload
    customer_message, private_note = conversation.messages.last(2)

    expect(@result[:terminal_action]).to eq('handoff')
    expect(@result[:customer_message]).to eq('I am transferring you to a billing specialist.')
    expect(conversation.status).to eq('open')
    expect(conversation.cached_label_list_array).to include('vip')
    expect(customer_message.private).to be(false)
    expect(customer_message.sender).to eq(ai_agent.agent_bot)
    expect(customer_message.content).to eq('I am transferring you to a billing specialist.')
    expect(private_note.private).to be(true)
    expect(private_note.sender).to eq(ai_agent.agent_bot)
    expect(private_note.content).to include(
      'AI handoff brief',
      "Reason\nBilling issue",
      "Context for the team\nCustomer needs finance review",
      "Labels\nvip"
    )
    expect(conversation.additional_attributes['ai_handoff_completed']).to eq(true)
    expect(conversation.additional_attributes['ai_handoff_by_ai_agent_id']).to eq(ai_agent.id)
    expect(conversation.additional_attributes['ai_handoff_message_id']).to eq(trigger_message.id)
  end

  it 'does not accept routing fields' do
    result = service.call(args: {
      'reason' => 'Escalation',
      'customer_message' => 'A human will continue helping you.',
      'internal_note' => 'Need help',
      'labels' => ['vip'],
      'team_id' => 123,
      'assignee_id' => 456
    })

    expect(result[:terminal_action]).to eq('handoff')
    expect(result).not_to have_key(:team_id)
    expect(result).not_to have_key(:assignee_id)
  end

  it 'bounds generated brief fields before saving the private note' do
    result = service.call(args: {
      'reason' => 'r' * 2_000,
      'customer_message' => 'A human will continue helping you.',
      'internal_note' => 'c' * 5_000,
      'labels' => ['vip']
    })

    expect(result[:private_note_preview]).not_to include('r' * 301)
    expect(result[:private_note_preview]).not_to include('c' * 1_501)
    expect(result[:private_note_preview].length).to be < 3_000
  end
end
