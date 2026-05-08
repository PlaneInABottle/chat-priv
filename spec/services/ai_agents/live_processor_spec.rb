require 'rails_helper'

RSpec.describe AiAgents::LiveProcessor do
  let(:account) { create(:account) }
  let!(:vip_label) { create(:label, account: account, title: 'vip') }
  let(:ai_agent) { create(:ai_agent, :with_human_handoff_tool, account: account, enabled: true) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: 'pending') }
  let(:adapter) { instance_double(AiAgents::LlmAdapters::OpenAiCompatibleAdapter) }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: ai_agent.agent_bot, status: 'active')
  end

  it 'executes live handoff for an eligible incoming customer message' do
    message = create(:message,
                     account: account,
                     inbox: inbox,
                     conversation: conversation,
                     message_type: 'incoming',
                     sender: conversation.contact,
                     content: 'I need billing help')

    allow(adapter).to receive(:perform).and_return({
      assistant_text: nil,
      tool_calls: [{ id: 'call_1', type: 'function', name: 'human_handoff', arguments: { reason: 'Need help', internal_note: 'Escalate to billing', labels: ['vip'] }.to_json }],
      finish_reason: 'tool_calls'
    })

    result = described_class.new(message: message, adapter: adapter).perform

    expect(result).to eq(true)
    expect(conversation.reload.additional_attributes['ai_handoff_completed']).to eq(true)
    expect(conversation.status).to eq('open')
    expect(conversation.messages.where(private: true).last.content).to eq('Escalate to billing')
  end

  it 'does not execute for private notes' do
    message = create(:message,
                     account: account,
                     inbox: inbox,
                     conversation: conversation,
                     message_type: 'incoming',
                     private: true,
                     sender: conversation.contact)

    expect(adapter).not_to receive(:perform)

    expect(described_class.new(message: message, adapter: adapter).perform).to be_nil
  end

  it 'does not execute for outgoing bot messages' do
    message = create(:message,
                     account: account,
                     inbox: inbox,
                     conversation: conversation,
                     message_type: 'outgoing',
                     sender: ai_agent.agent_bot,
                     content: 'Bot reply')

    expect(adapter).not_to receive(:perform)

    expect(described_class.new(message: message, adapter: adapter).perform).to be_nil
  end

  it 'does not re-enter after handoff is completed' do
    conversation.update!(additional_attributes: { 'ai_handoff_completed' => true })
    message = create(:message,
                     account: account,
                     inbox: inbox,
                     conversation: conversation,
                     message_type: 'incoming',
                     sender: conversation.contact)

    expect(adapter).not_to receive(:perform)

    expect(described_class.new(message: message, adapter: adapter).perform).to be_nil
  end
end
