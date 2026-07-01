require 'rails_helper'

RSpec.describe AiAgents::LiveProcessor do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
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
                                                     tool_calls: [handoff_tool_call],
                                                     finish_reason: 'tool_calls'
                                                   })

    result = described_class.new(message: message, adapter: adapter).perform

    expect(result).to be(true)
    expect(conversation.reload.additional_attributes['ai_handoff_completed']).to be(true)
    expect(conversation.status).to eq('open')
    expect(conversation.cached_label_list_array).to include(vip_label.title)
    expect(conversation.messages.where(private: true).last.content).to eq('Escalate to billing')
    expect(conversation.messages.where(private: false).last.content).to eq('I am transferring you to a human agent.')
  end

  def handoff_tool_call
    { id: 'call_1', type: 'function', name: 'human_handoff', arguments: handoff_arguments.to_json }
  end

  def handoff_arguments
    { reason: 'Need help', customer_message: 'I am transferring you to a human agent.', internal_note: 'Escalate to billing', labels: ['vip'] }
  end

  it 'persists one outgoing AgentBot response for a text assistant result' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                               content: 'Hello')
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Hi there', tool_calls: [], finish_reason: 'stop' })

    expect do
      described_class.new(message: message, adapter: adapter).perform
    end.to change { conversation.messages.where(message_type: 'outgoing', private: false, sender: ai_agent.agent_bot).count }.by(1)

    expect(conversation.messages.where(message_type: 'outgoing', private: false, sender: ai_agent.agent_bot).last.content).to eq('Hi there')
  end

  it 'consumes one monthly usage event for a successful live AI response' do
    account.update!(ai_agent_conversation_limit: 2, ai_agent_conversation_reuse_window_hours: 24)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                               content: 'Hello')
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Hi there', tool_calls: [], finish_reason: 'stop' })

    expect do
      described_class.new(message: message, adapter: adapter).perform
    end.to change(AiAgentUsageEvent.consumed, :count).by(1)

    expect(AiAgentUsageEvent.last).to have_attributes(account_id: account.id, ai_agent_id: ai_agent.id, contact_id: conversation.contact_id)
  end

  it 'does not consume another usage event for the same contact inside the reuse window' do
    account.update!(ai_agent_conversation_limit: 2, ai_agent_conversation_reuse_window_hours: 24)
    create(:ai_agent_usage_event,
           account: account,
           ai_agent: ai_agent,
           contact: conversation.contact,
           conversation: conversation,
           window_ends_at: 2.hours.from_now,
           status: :consumed)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                               content: 'Hello again')
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Hi there', tool_calls: [], finish_reason: 'stop' })

    expect do
      described_class.new(message: message, adapter: adapter).perform
    end.not_to change(AiAgentUsageEvent, :count)
  end

  it 'hands off silently without calling the LLM when monthly usage is exhausted' do
    account.update!(ai_agent_conversation_limit: 1, ai_agent_conversation_reuse_window_hours: 1)
    create(:ai_agent_usage_event,
           account: account,
           ai_agent: ai_agent,
           contact: create(:contact, account: account),
           period_start_at: Time.current.beginning_of_month,
           period_end_at: Time.current.next_month.beginning_of_month,
           window_started_at: 2.days.ago,
           window_ends_at: 1.day.ago,
           status: :consumed)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                               content: 'Need help')

    expect(adapter).not_to receive(:perform)

    expect do
      result = described_class.new(message: message, adapter: adapter).perform
      expect(result).to be(true)
    end.to change { conversation.messages.where(private: true).count }.by(1)
      .and change { conversation.messages.where(message_type: 'outgoing', private: false, sender: ai_agent.agent_bot).count }.by(0)

    expect(conversation.reload).to be_open
    expect(conversation.additional_attributes['ai_usage_limit_exhausted']).to be(true)
  end

  it 'passes recent public conversation messages ordered by id' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                     content: 'Old')
    boundary = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing', sender: ai_agent.agent_bot,
                                content: 'Boundary')
    first = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                             content: 'One')
    second = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                              content: 'Two')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                     content: 'Future')
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Done', tool_calls: [], finish_reason: 'stop' })

    described_class.new(message: second, adapter: adapter).perform

    expect(adapter).to have_received(:perform).with(hash_including(messages: [
                                                                     { role: 'user', content: 'Old' },
                                                                     { role: 'assistant', content: boundary.content },
                                                                     { role: 'user', content: first.content },
                                                                     { role: 'user', content: second.content }
                                                                   ]))
  end

  it 'keeps recent AI replies in context for follow-up customer messages' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming',
                     sender: conversation.contact, content: '70x80')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'outgoing', sender: ai_agent.agent_bot,
                     content: 'Akordeon Pencere Sineklik Beyaz is one option.')
    latest = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                              content: 'beyaz olanin linki var mi')
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Done', tool_calls: [], finish_reason: 'stop' })

    described_class.new(message: latest, adapter: adapter).perform

    expect(adapter).to have_received(:perform).with(hash_including(messages: [
                                                                     { role: 'user', content: '70x80' },
                                                                     { role: 'assistant',
                                                                       content: 'Akordeon Pencere Sineklik Beyaz is one option.' },
                                                                     { role: 'user', content: latest.content }
                                                                   ]))
    expect(AiAgentLlmCall.last.request_messages.last(3)).to eq([
                                                                 { 'role' => 'user', 'content' => '70x80' },
                                                                 { 'role' => 'assistant',
                                                                   'content' => 'Akordeon Pencere Sineklik Beyaz is one option.' },
                                                                 { 'role' => 'user', 'content' => latest.content }
                                                               ])
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

  it 'does not execute for voice call messages' do
    message = create(:message,
                     account: account,
                     inbox: inbox,
                     conversation: conversation,
                     message_type: 'incoming',
                     content_type: 'voice_call',
                     sender: conversation.contact)

    expect(adapter).not_to receive(:perform)

    expect(described_class.new(message: message, adapter: adapter).perform).to be_nil
  end

  it 'does not execute when AI Agent is disabled for the account' do
    account.update!(ai_agent_enabled: false)
    message = create(:message,
                     account: account,
                     inbox: inbox,
                     conversation: conversation,
                     message_type: 'incoming',
                     sender: conversation.contact,
                     content: 'Hello')
    outgoing_messages = conversation.messages.where(message_type: 'outgoing', private: false, sender: ai_agent.agent_bot)

    expect(adapter).not_to receive(:perform)
    expect do
      described_class.new(message: message, adapter: adapter).perform
    end.not_to change(outgoing_messages, :count)
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
