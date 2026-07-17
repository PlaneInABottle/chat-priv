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

    outgoing = conversation.messages.where(message_type: 'outgoing', private: false, sender: ai_agent.agent_bot).last
    expect(outgoing.content).to eq('Hi there')
    expect(outgoing.content_attributes.dig('ai_agent', 'turn_telemetry')).to include(
      'catalog_search_units_used' => 0,
      'order_lookup_used' => 0,
      'handoff_used' => false,
      'budget_exhausted' => false,
      'final_answer_source' => 'model_only'
    )
    expect(outgoing.content_attributes.dig('ai_agent', 'trigger_message_id')).to eq(message.id)
  end

  it 'does not generate another reply when the same customer message is delivered twice' do
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                               content: 'Hello again')
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Hi there', tool_calls: [], finish_reason: 'stop' })

    2.times { described_class.new(message: message, adapter: adapter).perform }

    replies = conversation.messages.where(message_type: 'outgoing', private: false, sender: ai_agent.agent_bot)
    expect(replies.count).to eq(1)
    expect(adapter).to have_received(:perform).once
  end

  it 'rolls back the outgoing reply when usage consumption fails before retry' do
    account.update!(ai_agent_conversation_limit: 2, ai_agent_conversation_reuse_window_hours: 24)
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                               content: 'Hello with accounting')
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Hi there', tool_calls: [], finish_reason: 'stop' })
    consume_attempts = 0
    allow(AiAgents::Usage::Limiter).to receive(:new).and_wrap_original do |method, **args|
      limiter = method.call(**args)
      allow(limiter).to receive(:consume!).and_wrap_original do |consume_method, *consume_args|
        consume_attempts += 1
        raise ActiveRecord::ConnectionTimeoutError, 'temporary database failure' if consume_attempts == 1

        consume_method.call(*consume_args)
      end
      limiter
    end

    expect do
      described_class.new(message: message, adapter: adapter).perform
    end.to raise_error(ActiveRecord::ConnectionTimeoutError, 'temporary database failure')
    expect(conversation.messages.where(message_type: 'outgoing', private: false, sender: ai_agent.agent_bot)).to be_empty

    described_class.new(message: message, adapter: adapter).perform

    expect(conversation.messages.where(message_type: 'outgoing', private: false, sender: ai_agent.agent_bot).count).to eq(1)
  end

  it 'persists one outgoing input selection for a supported live widget inbox' do
    widget = create(:channel_widget, account: account)
    widget_conversation = create(:conversation, account: account, inbox: widget.inbox, status: 'pending')
    create(:agent_bot_inbox, inbox: widget.inbox, agent_bot: ai_agent.agent_bot, status: 'active')
    message = create(
      :message,
      account: account,
      inbox: widget.inbox,
      conversation: widget_conversation,
      message_type: 'incoming',
      sender: widget_conversation.contact,
      content: 'Yardıma ihtiyacım var'
    )
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [
          {
            id: 'options-1',
            type: 'function',
            name: 'present_options',
            arguments: {
              question: 'Nasıl devam edelim?',
              options: [{ label: 'Ürün seçimi' }, { label: 'Sipariş desteği' }]
            }.to_json
          }
        ],
        finish_reason: 'tool_calls'
      }
    )

    expect do
      described_class.new(message: message, adapter: adapter).perform
    end.to change { widget_conversation.messages.outgoing.where(private: false, sender: ai_agent.agent_bot).count }.by(1)

    outgoing = widget_conversation.messages.outgoing.where(private: false, sender: ai_agent.agent_bot).last
    expect(outgoing).to have_attributes(content: 'Nasıl devam edelim?', content_type: 'input_select')
    expect(outgoing.content_attributes['items'].pluck('title')).to eq(['Ürün seçimi', 'Sipariş desteği'])
    expect(outgoing.content_attributes.dig('ai_agent', 'selection', 'version')).to eq(1)
    expect(outgoing.content_attributes.to_json).not_to include('present_options', 'tool_events')
  end

  it 'uses shared recommendation rules without native option mechanics on API channels' do
    api_channel = create(:channel_api, account: account)
    api_conversation = create(:conversation, account: account, inbox: api_channel.inbox, status: 'pending')
    create(:agent_bot_inbox, inbox: api_channel.inbox, agent_bot: ai_agent.agent_bot, status: 'active')
    message = create(
      :message,
      account: account,
      inbox: api_channel.inbox,
      conversation: api_conversation,
      message_type: 'incoming',
      sender: api_conversation.contact,
      content: 'Bütçem düşük, balkon kapısı için sen öner'
    )
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Kısa öneri', tool_calls: [], finish_reason: 'stop' })
    adapter_options = nil
    allow(AiAgents::LlmAdapters::OpenAiCompatibleAdapter).to receive(:new) do |**options|
      adapter_options = options
      adapter
    end

    described_class.new(message: message).perform

    llm_call = AiAgentLlmCall.last
    system_prompt = llm_call.request_messages.first.fetch('content')
    expect(llm_call.request_tool_names).not_to include('present_options')
    expect(system_prompt).to include('Shared conversation rules:', 'interactive choices are unavailable')
    expect(system_prompt).not_to include('Customer option rules:', '`present_options`')
    expect(adapter_options.dig(:llm_options, :system_prompt)).to eq(system_prompt)
  end

  it 'uses the published prompt and capabilities while an update remains in draft' do
    ai_agent.update!(prompt: 'Published customer guidance')
    ai_agent.mark_test_succeeded!
    ai_agent.publish!
    ai_agent.update!(
      prompt: 'Unpublished draft guidance',
      config: { 'tools' => { 'enabled' => %w[human_handoff ikas_catalog_search] } }
    )
    message = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact,
                               content: 'Hello')
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Hi there', tool_calls: [], finish_reason: 'stop' })

    described_class.new(message: message, adapter: adapter).perform

    system_prompt = AiAgentLlmCall.last.request_messages.first.fetch('content')
    expect(system_prompt).to include('Published customer guidance')
    expect(system_prompt).not_to include('Unpublished draft guidance')
    expect(AiAgentLlmCall.last.request_tool_names).to eq(%w[human_handoff present_options])
  end

  it 'uses published knowledge and persists compact source attribution' do
    source = create(
      :ai_knowledge_source,
      account: account,
      name: 'Returns and exchanges',
      content: 'Custom-sized products are reviewed for return within 14 days.'
    )
    AiKnowledgeSourceAssignment.create!(assistant: ai_agent, ai_knowledge_source: source)
    ai_agent.mark_test_succeeded!
    ai_agent.publish!
    source.update!(content: 'Unpublished draft now says 30 days.')
    message = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: 'incoming',
      sender: conversation.contact,
      content: 'Can I return a custom-sized product?'
    )
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [
          {
            id: 'knowledge-1',
            type: 'function',
            name: 'search_knowledge',
            arguments: { query: 'custom product return within 14 days' }.to_json
          }
        ],
        finish_reason: 'tool_calls'
      },
      {
        assistant_text: 'Custom-sized products can be reviewed for return within 14 days.',
        tool_calls: [],
        finish_reason: 'stop'
      }
    )

    described_class.new(message: message, adapter: adapter).perform

    tool_result_message = AiAgentLlmCall.last.request_messages.find { |entry| entry['role'] == 'tool' }
    expect(tool_result_message['content']).to include('within 14 days')
    expect(tool_result_message['content']).not_to include('30 days')
    outgoing = conversation.messages.where(message_type: 'outgoing', private: false, sender: ai_agent.agent_bot).last
    expect(outgoing.content_attributes.dig('ai_agent', 'source_attributions')).to eq(
      [{ 'source_id' => source.id, 'source_name' => 'Returns and exchanges' }]
    )
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
