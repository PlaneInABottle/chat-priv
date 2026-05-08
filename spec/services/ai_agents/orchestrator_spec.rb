require 'rails_helper'

RSpec.describe AiAgents::Orchestrator do
  let(:account) { create(:account) }
  let!(:vip_label) { create(:label, account: account, title: 'vip') }
  let(:ai_agent) do
    create(:ai_agent, :with_human_handoff_tool, account: account, enabled: true)
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:trigger_message) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact)
  end
  let(:adapter) { instance_double(AiAgents::LlmAdapters::OpenAiCompatibleAdapter) }

  it 'returns assistant text for text-only turns' do
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Hello there', tool_calls: [], finish_reason: 'stop' })

    result = described_class.new(ai_agent: ai_agent, messages: [{ role: 'user', content: 'Hi' }], mode: :test, adapter: adapter).perform

    expect(result[:assistant_message]['content']).to eq('Hello there')
    expect(result[:tool_events]).to eq([])
  end

  it 'tolerates legacy human handoff config keys when generating responses' do
    ai_agent.update_column(:config, {
                             'tools' => {
                               'enabled' => ['human_handoff'],
                               'human_handoff' => {
                                 'allowed_labels' => ['vip'],
                                 'preview_only' => true,
                                 'transfer_message' => 'Please wait.'
                               }
                             }
                           })
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Hello there', tool_calls: [], finish_reason: 'stop' })

    result = described_class.new(ai_agent: ai_agent.reload, messages: [{ role: 'user', content: 'Hi' }], mode: :test, adapter: adapter).perform

    expect(result[:assistant_message]['content']).to eq('Hello there')
    expect(adapter).to have_received(:perform)
  end

  it 'returns terminal handoff preview for human_handoff tool turns' do
    allow(adapter).to receive(:perform).and_return({
      assistant_text: nil,
      tool_calls: [{ id: 'call_1', type: 'function', name: 'human_handoff', arguments: { reason: 'Need help', customer_message: 'A human teammate will take over next.', internal_note: 'Escalate', labels: ['vip'] }.to_json }],
      finish_reason: 'tool_calls'
    })

    result = described_class.new(ai_agent: ai_agent, messages: [{ role: 'user', content: 'Hi' }], mode: :test, adapter: adapter).perform

    expect(result[:terminal_action]).to eq('handoff')
    expect(result[:assistant_message]['content']).to eq('A human teammate will take over next.')
    expect(result[:assistant_message]['tool_result']['customer_message']).to eq('A human teammate will take over next.')
    expect(result[:assistant_message]['tool_result']['private_note_preview']).to eq('Escalate')
    expect(result[:assistant_message]['tool_result']['labels_to_apply']).to eq(['vip'])
    expect(result[:assistant_message]['tool_result']['labels_requested']).to eq(['vip'])
    expect(result[:assistant_message]['tool_result']['labels_ignored']).to eq([])
    expect(result[:assistant_message]['tool_result']['conversation_status']).to eq('open')
  end

  it 'executes live handoff side effects when mode is live' do
    allow(adapter).to receive(:perform).and_return({
      assistant_text: nil,
      tool_calls: [{ id: 'call_1', type: 'function', name: 'human_handoff', arguments: { reason: 'Need help', customer_message: 'A human teammate will take over next.', internal_note: 'Escalate', labels: ['vip'] }.to_json }],
      finish_reason: 'tool_calls'
    })

    result = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Hi' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(result[:terminal_action]).to eq('handoff')
    expect(conversation.reload.additional_attributes['ai_handoff_completed']).to eq(true)
    expect(conversation.messages.last.private).to be(true)
    expect(conversation.cached_label_list_array).to include('vip')
  end

  it 'rejects multiple tool calls safely' do
    allow(adapter).to receive(:perform).and_return({
      assistant_text: nil,
      tool_calls: [
        { id: 'call_1', type: 'function', name: 'human_handoff', arguments: '{}'},
        { id: 'call_2', type: 'function', name: 'human_handoff', arguments: '{}'}
      ],
      finish_reason: 'tool_calls'
    })

    result = described_class.new(ai_agent: ai_agent, messages: [{ role: 'user', content: 'Hi' }], mode: :test, adapter: adapter).perform

    expect(result[:assistant_message]['content']).to include('could not complete')
    expect(result[:tool_events].first['error_code']).to eq('multiple_tool_calls')
  end
end
