require 'rails_helper'

RSpec.describe AiAgents::Orchestrator do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let!(:vip_label) { create(:label, account: account, title: 'vip') }
  let(:ai_agent) do
    create(:ai_agent, :with_human_handoff_tool, account: account, enabled: true)
  end
  let(:conversation) { create(:conversation, account: account) }
  let(:trigger_message) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact)
  end
  let(:adapter) { instance_double(AiAgents::LlmAdapters::OpenAiCompatibleAdapter) }

  it 'does not call the adapter when AI Agent is disabled for the account' do
    account.update!(ai_agent_enabled: false)

    expect(adapter).not_to receive(:perform)

    result = described_class.new(ai_agent: ai_agent, messages: [{ role: 'user', content: 'Hi' }], mode: :test, adapter: adapter).perform

    expect(result).to eq(assistant_message: nil, tool_events: [], terminal_action: nil)
  end

  it 'returns assistant text for text-only turns' do
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'Hello there', tool_calls: [], finish_reason: 'stop' })

    result = nil
    expect do
      result = described_class.new(ai_agent: ai_agent, messages: [{ role: 'user', content: 'Hi' }], mode: :test, adapter: adapter).perform
    end.to change(AiAgentLlmCall, :count).by(1)

    expect(result[:assistant_message]['content']).to eq('Hello there')
    expect(result[:tool_events]).to eq([])
    expect(AiAgentLlmCall.last.request_messages.last).to eq('role' => 'user', 'content' => 'Hi')
    expect(AiAgentLlmCall.last.response).to include('assistant_text' => 'Hello there', 'finish_reason' => 'stop')
  end

  it 'retries once when the provider returns an empty response without tool calls' do
    allow(adapter).to receive(:perform).and_return(
      { assistant_text: nil, tool_calls: [], finish_reason: 'stop' },
      { assistant_text: 'Retry answer', tool_calls: [], finish_reason: 'stop' }
    )

    result = nil
    expect do
      result = described_class.new(ai_agent: ai_agent, messages: [{ role: 'user', content: 'Hi' }], mode: :test, adapter: adapter).perform
    end.to change(AiAgentLlmCall, :count).by(2)

    expect(result[:assistant_message]['content']).to eq('Retry answer')
    expect(adapter).to have_received(:perform).twice
    expect(AiAgentLlmCall.last.step).to eq('initial_retry')
    expect(AiAgentLlmCall.last.request_messages.last['content']).to include('previous AI response was empty')
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

  it 'lets handoff win when the model mixes handoff with other tools' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => %w[human_handoff ikas_catalog_search], 'human_handoff' => { 'allowed_labels' => ['vip'] } } })
    allow(adapter).to receive(:perform).and_return({
      assistant_text: nil,
      tool_calls: [
        { id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'kapı sineklik' }.to_json },
        { id: 'call_2', type: 'function', name: 'human_handoff', arguments: { reason: 'Customer wants a person', customer_message: 'Sizi bir temsilciye aktarıyorum.', internal_note: 'Customer asked for human help', labels: ['vip'] }.to_json }
      ],
      finish_reason: 'tool_calls'
    })

    result = described_class.new(ai_agent: ai_agent, messages: [{ role: 'user', content: 'Hi' }], mode: :test, adapter: adapter).perform

    expect(result[:terminal_action]).to eq('handoff')
    expect(result[:assistant_message]['content']).to eq('Sizi bir temsilciye aktarıyorum.')
    expect(result[:tool_events].map { |event| event['tool'] }).to eq(['human_handoff'])
    expect(AiAgentToolExecution.last.tool_key).to eq('human_handoff')
  end

  it 'redacts customer identifiers before the order lookup follow-up LLM call' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_lookup_order'] } })
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: { 'tool' => 'ikas_lookup_order', 'status' => 'ok' },
      tool_result: { status: 'ok', result_type: 'no_match', orders: [] }
    )
    executor = instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
        {
          assistant_text: nil,
          tool_calls: [{ id: 'call_1', type: 'function', name: 'ikas_lookup_order', arguments: '{}' }],
          finish_reason: 'tool_calls'
        }
      else
        { assistant_text: 'No matching order found.', tool_calls: [], finish_reason: 'stop' }
      end
    end

    described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'siparis TEST-12345 test@example.com +90 555 123 45 67' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    follow_up_user_message = calls.second.fetch(:messages).find { |message| message[:role] == 'user' }
    expect(follow_up_user_message[:content]).to include('[email redacted]', '[phone redacted]', 'TEST-12345')
    expect(follow_up_user_message[:content]).not_to include('test@example.com', '+90 555 123 45 67')
  end

  it 'answers catalog needs_scope through the follow-up prompt' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: { 'tool' => 'ikas_catalog_search', 'status' => 'ok' },
      tool_result: { status: 'ok', result_type: 'needs_scope', candidates: [] }
    )
    executor = instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [{ id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: '70x80' }.to_json }],
        finish_reason: 'tool_calls'
      },
      { assistant_text: 'Hangi ürün için 70x80 ölçüyü kontrol edelim?', tool_calls: [], finish_reason: 'stop' },
      { assistant_text: 'Hangi ürün için 70x80 ölçüyü kontrol edelim?', tool_calls: [], finish_reason: 'stop' }
    )

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: '70x80' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to eq('Hangi ürün için 70x80 ölçüyü kontrol edelim?')
    expect(adapter).to have_received(:perform).exactly(3).times
  end

  it 'answers catalog no_match through the follow-up prompt as a normal search outcome' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    tool_result = { status: 'ok', result_type: 'no_match', query: 'mor unicorn sineklik', result_count: 0, candidates: [] }
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: { 'tool' => 'ikas_catalog_search', 'status' => 'ok', 'result' => tool_result.deep_stringify_keys },
      tool_result: tool_result
    )
    executor = instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
        {
          assistant_text: nil,
          tool_calls: [{ id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'mor unicorn sineklik' }.to_json }],
          finish_reason: 'tool_calls'
        }
      elsif calls.length == 2
        { assistant_text: 'Mor unicorn sineklik için katalogda net eşleşme bulamadım. Ölçü veya ürün tipini paylaşır mısınız?', tool_calls: [], finish_reason: 'stop' }
      else
        { assistant_text: 'Mor unicorn sineklik için katalogda net eşleşme bulamadım. Ölçü veya ürün tipini paylaşır mısınız?', tool_calls: [], finish_reason: 'stop' }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'mor unicorn sineklik var mi' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to eq('mor unicorn sineklik için net bir ürün bulamadım. Ürün adını, kategori bilgisini veya aradığınız özelliği biraz daha net paylaşır mısınız?')
    expect(result[:assistant_message]['content']).not_to include('sineklik kategorileri', 'mağazamızda şunlar')
    expect(result[:assistant_message]['turn_telemetry']).to include(
      'catalog_search_units_used' => 1,
      'handoff_used' => false,
      'final_answer_source' => 'tool_evidence'
    )
    expect(adapter).to have_received(:perform).exactly(3).times
    expect(AiAgentLlmCall.pluck(:step)).to include('customer_facing_finalizer')
  end

  it 'retries the finalizer when it attempts to call tools after tool-backed evidence is available' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: { 'tool' => 'ikas_catalog_search', 'status' => 'ok', 'tool_call_id' => 'call_1' },
      tool_result: { status: 'ok', result_type: 'no_match', candidates: [] }
    )
    executor = instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
        {
          assistant_text: nil,
          tool_calls: [{ id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: '200x300 sineklik' }.to_json }],
          finish_reason: 'tool_calls'
        }
      elsif calls.length == 2
        {
          assistant_text: '200x300 cm ölçü için net eşleşme bulamadım. Hangi sineklik tipini düşündüğünüzü paylaşır mısınız?',
          tool_calls: [],
          finish_reason: 'stop'
        }
      elsif calls.length == 3
        {
          assistant_text: nil,
          tool_calls: [{ id: 'call_2', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'sürme sineklik max' }.to_json }],
          finish_reason: 'tool_calls'
        }
      else
        {
          assistant_text: '200x300 cm ölçü için katalogda net eşleşme bulamadım. Hangi sineklik tipini düşündüğünüzü paylaşır mısınız?',
          tool_calls: [],
          finish_reason: 'stop'
        }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: '200x300 cm ölçüsünde sineklik olur mu?' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(result[:terminal_action]).to be_nil
    expect(result[:assistant_message]['content']).to include('net eşleşme bulamadım')
    expect(result[:assistant_message]['turn_telemetry']).to include(
      'catalog_search_units_used' => 1,
      'handoff_used' => false,
      'final_answer_source' => 'tool_evidence'
    )
    expect(result[:tool_events].map { |event| event['tool'] }).to eq(['ikas_catalog_search'])
    expect(adapter).to have_received(:perform).exactly(4).times
    expect(AiAgentLlmCall.pluck(:step)).to include('customer_facing_finalizer_retry')
  end

  it 'retries the finalizer when it emits tool-call markup as text' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: { 'tool' => 'ikas_catalog_search', 'status' => 'ok', 'tool_call_id' => 'call_1' },
      tool_result: { status: 'ok', result_type: 'show_candidates', candidates: [{ display_name: 'Kedi Tüllü Pencere Sineklik' }] }
    )
    executor = instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
        {
          assistant_text: nil,
          tool_calls: [{ id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'kedi tüllü sineklik' }.to_json }],
          finish_reason: 'tool_calls'
        }
      elsif calls.length == 2
        { assistant_text: 'Kedi tüllü pencere sineklik seçenekleri mevcut.', tool_calls: [], finish_reason: 'stop' }
      elsif calls.length == 3
        {
          assistant_text: "<｜｜DSML｜｜tool_calls>\n<｜｜DSML｜｜invoke name=\"ikas_catalog_search\">\n</｜｜DSML｜｜invoke>\n</｜｜DSML｜｜tool_calls>",
          tool_calls: [],
          finish_reason: 'stop'
        }
      else
        { assistant_text: 'Kedi tüllü pencere sineklik seçenekleri mevcut.', tool_calls: [], finish_reason: 'stop' }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'kedi tüllü sineklik var mı' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to eq('Kedi tüllü pencere sineklik seçenekleri mevcut.')
    expect(result[:assistant_message]['content']).not_to include('DSML', 'tool_calls')
    expect(adapter).to have_received(:perform).exactly(4).times
    expect(AiAgentLlmCall.pluck(:step)).to include('customer_facing_finalizer_retry')
  end

  it 'scrubs non-final reference prices when the finalizer repeats them after retry' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    tool_result = {
      status: 'ok',
      result_type: 'show_candidates',
      candidates: [
        {
          display_name: 'Orjin Pliseli Perde Antrasit',
          price: {
            amount: nil,
            reference_amount: 12.94,
            compare_at_reference_amount: nil,
            final_total_known: false,
            pricing_model: 'custom_options'
          },
          link: { url: 'https://example.test/perde' }
        }
      ]
    }
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: {
        'tool' => 'ikas_catalog_search',
        'status' => 'ok',
        'tool_call_id' => 'call_1',
        'result' => tool_result.deep_stringify_keys
      },
      tool_result: tool_result
    )
    executor = instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
        {
          assistant_text: nil,
          tool_calls: [{ id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'orjin pliseli perde antrasit' }.to_json }],
          finish_reason: 'tool_calls'
        }
      elsif calls.length == 2
        { assistant_text: 'Orjin Pliseli Perde Antrasit özel ölçüyle fiyatlanır.', tool_calls: [], finish_reason: 'stop' }
      elsif calls.length == 3
        { assistant_text: 'Gördüğünüz **12,94 TL** tutarı nihai fiyat değildir.', tool_calls: [], finish_reason: 'stop' }
      else
        { assistant_text: 'Gördüğünüz **12,94 TL** tutarı nihai fiyat değildir. Ölçü ve seçeneklere göre değişir.', tool_calls: [], finish_reason: 'stop' }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Bu 12,94 TL fiyat 70x80 perde için doğru mu?' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to include('Gördüğünüz tutar')
    expect(result[:assistant_message]['content']).not_to include('12,94', '12.94', 'TL')
    expect(adapter).to have_received(:perform).exactly(4).times
    expect(AiAgentLlmCall.pluck(:step)).to include('customer_facing_finalizer_retry')
  end

  it 'finalizes tool-backed drafts into customer-facing replies without exposing internal process' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: { 'tool' => 'ikas_catalog_search', 'status' => 'ok', 'tool_call_id' => 'call_1' },
      tool_result: {
        status: 'ok',
        result_type: 'show_candidates',
        candidates: [{ display_name: 'KEDİ Tüllü Akordeon Kapı Sineklik', link: { url: 'https://example.test/sineklik' } }]
      }
    )
    executor = instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
        {
          assistant_text: nil,
          tool_calls: [{ id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'kedi tüllü balkon kapı sineklik' }.to_json }],
          finish_reason: 'tool_calls'
        }
      elsif calls.length == 2
        {
          assistant_text: 'Elimdeki 3 arama sonucuna göre KEDİ Tüllü Akordeon Kapı Sineklik uygun görünüyor.',
          tool_calls: [],
          finish_reason: 'stop'
        }
      else
        {
          assistant_text: 'KEDİ Tüllü Akordeon Kapı Sineklik balkon kapısı için uygun seçeneklerden biri. Link: https://example.test/sineklik',
          tool_calls: [],
          finish_reason: 'stop'
        }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'balkon kapısı için kedi tüllü sineklik önerir misin' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to eq('KEDİ Tüllü Akordeon Kapı Sineklik balkon kapısı için uygun seçeneklerden biri. Link: https://example.test/sineklik')
    expect(calls.third.fetch(:messages).pluck(:content).compact.join(' ')).not_to include('Elimdeki 3 arama sonucuna göre')
    expect(calls.third.fetch(:messages).pluck(:content).compact.join(' ')).to include('latest customer message controls the product/category scope')
    expect(calls.third.fetch(:messages).pluck(:content).compact.join(' ')).to include('Avoid robotic field-label blocks')
    expect(AiAgentLlmCall.last.step).to eq('customer_facing_finalizer')
  end

  it 'allows bounded catalog follow-up tool calls before the final answer' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    first_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: { 'tool' => 'ikas_catalog_search', 'status' => 'ok', 'tool_call_id' => 'call_1' },
      tool_result: { status: 'ok', result_type: 'show_candidates', candidates: [{ display_name: 'Menteşeli Kapı Sineklik Antrasit' }] }
    )
    second_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: { 'tool' => 'ikas_catalog_search', 'status' => 'ok', 'tool_call_id' => 'call_2' },
      tool_result: { status: 'ok', result_type: 'show_candidates', candidates: [{ display_name: 'Pilise Kapı Sineklik' }] }
    )
    third_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: { 'tool' => 'ikas_catalog_search', 'status' => 'ok', 'tool_call_id' => 'call_3' },
      tool_result: { status: 'ok', result_type: 'show_candidates', candidates: [{ display_name: 'Akordiyon Kapı Sineklik' }] }
    )
    executor = instance_double(AiAgents::ToolExecutor)
    allow(executor).to receive(:execute).and_return(first_execution, second_execution, third_execution)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
        {
          assistant_text: nil,
          tool_calls: [{ id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'kapı sineklik' }.to_json }],
          finish_reason: 'tool_calls'
        }
      elsif calls.length == 2
        {
          assistant_text: nil,
          tool_calls: [
            { id: 'call_2', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'pilise kapı sineklik' }.to_json },
            { id: 'call_3', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'akordiyon kapı sineklik' }.to_json }
          ],
          finish_reason: 'tool_calls'
        }
      else
        { assistant_text: 'Menteşeli, pilise ve akordiyon seçeneklerini birlikte değerlendirebiliriz.', tool_calls: [], finish_reason: 'stop' }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'kedi için kapı sineklik önerir misin' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to include('Menteşeli, pilise ve akordiyon')
    expect(executor).to have_received(:execute).exactly(3).times
    expect(result[:assistant_message]['turn_telemetry']['catalog_search_units_used']).to eq(3)
  end

  it 'finalizes without tools when the catalog search budget is exhausted' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: { 'tool' => 'ikas_catalog_search', 'status' => 'ok', 'tool_call_id' => 'call_1' },
      tool_result: { status: 'ok', result_type: 'multi_search', queries: [] }
    )
    executor = instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
        {
          assistant_text: nil,
          tool_calls: [{ id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { queries: ['kapı sineklik', 'pilise sineklik', 'akordiyon sineklik'] }.to_json }],
          finish_reason: 'tool_calls'
        }
      elsif calls.length == 2
        {
          assistant_text: nil,
          tool_calls: [{ id: 'call_2', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'perde' }.to_json }],
          finish_reason: 'tool_calls'
        }
      else
        { assistant_text: 'Kapı için menteşeli, pilise ve akordiyon sineklik seçeneklerini değerlendirebilirsiniz.', tool_calls: [], finish_reason: 'stop' }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'kapı için birkaç sineklik öner' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(calls.third[:tools]).to eq([])
    expect(result[:assistant_message]['content']).to include('menteşeli, pilise ve akordiyon')
    expect(result[:assistant_message]['content']).not_to include('arama', 'tool', 'bütçe')
    expect(result[:assistant_message]['turn_telemetry']).to include(
      'catalog_search_units_used' => 3,
      'budget_exhausted' => true
    )
  end
end
