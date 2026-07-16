require 'rails_helper'

RSpec.describe AiAgents::OptionSelectionService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:prompt_message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      content_type: :input_select,
      content: 'Choose one',
      content_attributes: {
        items: [{ title: 'Sales', value: 'sales-id' }, { title: 'Support', value: 'support-id' }],
        ai_agent: { selection: { version: 1 } }
      }
    )
  end

  it 'rechecks submitted state under the prompt lock after resolving an option' do
    stale_service = described_class.new(prompt_message: prompt_message, selected_value: 'sales-id')
    expect(stale_service.selected_item).to eq('title' => 'Sales', 'value' => 'sales-id')

    winner = described_class.new(prompt_message: prompt_message, selected_value: 'sales-id').record_response!(incoming_message('winner'))
    losing_message = incoming_message('loser')

    expect(stale_service.record_response!(losing_message)).to eq(winner)
    expect(losing_message).not_to be_persisted
    expect(conversation.messages.incoming.count).to eq(1)
  end

  private

  def incoming_message(source_id)
    conversation.messages.build(
      account: account,
      inbox: inbox,
      sender: contact,
      message_type: :incoming,
      source_id: source_id
    )
  end
end
