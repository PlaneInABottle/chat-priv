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
  let(:tool_availability) { instance_double(AiAgents::ToolAvailability) }

  before do
    allow(tool_availability).to receive(:available_keys) do |definitions|
      definitions.map(&:key) - [AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL]
    end
    allow(AiAgents::ToolAvailability).to receive(:new).with(account: account).and_return(tool_availability)
  end

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

  it 'propagates provider failures so the background job can retry' do
    allow(adapter).to receive(:perform).and_raise(Net::ReadTimeout, 'temporary provider timeout')

    expect do
      described_class.new(
        ai_agent: ai_agent,
        messages: [{ role: 'user', content: 'Hi' }],
        mode: :live,
        conversation: conversation,
        trigger_message: trigger_message,
        adapter: adapter
      ).perform
    end.to raise_error(Net::ReadTimeout)

    expect(AiAgentLlmCall.last).to have_attributes(status: 'failed', error_code: 'Net::ReadTimeout')
  end

  it 'regenerates model-only replies that contain internal tool protocol markup' do
    allow(adapter).to receive(:perform).and_return(
      { assistant_text: '<tool_calls>ikas_catalog_search</tool_calls>', tool_calls: [], finish_reason: 'stop' },
      { assistant_text: 'How can I help you today?', tool_calls: [], finish_reason: 'stop' }
    )

    result = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Hi' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to eq('How can I help you today?')
    expect(adapter).to have_received(:perform).twice
    expect(AiAgentLlmCall.pluck(:step)).to include('customer_facing_finalizer')
  end

  it 'searches runtime knowledge and attributes the sources used in the final answer' do
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
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
        }
      else
        { assistant_text: 'Custom-sized products can be reviewed for return within 14 days.', tool_calls: [], finish_reason: 'stop' }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Can I return a custom-sized product?' }],
      mode: :test,
      adapter: adapter,
      knowledge_sources_override: [
        { id: 12, name: 'Returns and exchanges', content: 'Custom-sized products are reviewed for return within 14 days.' }
      ]
    ).perform

    expect(calls.first[:tools].pluck(:function).pluck(:name)).to include('search_knowledge')
    expect(calls.second[:messages].last[:content]).to include('Returns and exchanges', 'within 14 days')
    expect(result[:assistant_message]['source_attributions']).to eq(
      [{ 'source_id' => 12, 'source_name' => 'Returns and exchanges' }]
    )
    expect(result[:assistant_message]['turn_telemetry']).to include(
      'knowledge_searches_used' => 1,
      'knowledge_sources_used' => 1,
      'final_answer_source' => 'knowledge_evidence'
    )
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

  it 'hands off instead of silently dropping the turn when the empty-response retry is also empty' do
    allow(adapter).to receive(:perform).and_return(
      { assistant_text: nil, tool_calls: [], finish_reason: 'stop' },
      { assistant_text: nil, tool_calls: [], finish_reason: 'stop' }
    )

    result = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Hi' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:terminal_action]).to eq('handoff')
    expect(result[:assistant_message]['content']).to be_present
    expect(adapter).to have_received(:perform).twice
  end

  it 'does not advertise integration tools that are unavailable at runtime' do
    allow(tool_availability).to receive(:available_keys).and_return(['human_handoff'])
    ai_agent.update!(config: { 'tools' => { 'enabled' => %w[human_handoff ikas_lookup_order ikas_catalog_search] } })
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      { assistant_text: 'Hello', tool_calls: [], finish_reason: 'stop' }
    end

    described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Where is my order?' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    advertised_names = calls.first.fetch(:tools).pluck(:function).pluck(:name)
    expect(advertised_names).to eq(['human_handoff'])
  end

  it 'keeps valid mixed tool calls when another tool budget is exhausted' do
    orchestrator = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Check both sources.' }],
      mode: :test,
      adapter: adapter
    )
    counts = orchestrator.send(:executed_tool_counts)
    counts[AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL] = described_class::MAX_CATALOG_SEARCH_QUERY_UNITS
    catalog_call = {
      id: 'catalog-over-budget',
      type: 'function',
      name: 'ikas_catalog_search',
      arguments: { query: 'door screen' }.to_json
    }
    knowledge_call = {
      id: 'knowledge-with-budget',
      type: 'function',
      name: 'search_knowledge',
      arguments: { query: 'return policy' }.to_json
    }

    calls, rejection_code = orchestrator.send(:bounded_tool_calls, [catalog_call, knowledge_call])

    expect(calls).to eq([knowledge_call])
    expect(rejection_code).to be_nil
  end

  it 'retries a catalog answer cut off by the provider output limit' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    tool_result = {
      status: 'ok',
      result_type: 'show_candidates',
      candidates: [{ display_name: 'Menteşeli Kapı Sinekliği', price: { amount: 2500, currency: 'TRY', final_total_known: true } }]
    }
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: {
        'tool' => 'ikas_catalog_search',
        'status' => 'ok',
        'tool_call_id' => 'catalog-1',
        'result' => tool_result.deep_stringify_keys
      },
      tool_result: tool_result
    )
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(
      instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    )
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [
          {
            id: 'catalog-1',
            type: 'function',
            name: 'ikas_catalog_search',
            arguments: { query: 'düşük bütçeli kedi tüllü balkon kapısı sineklik' }.to_json
          }
        ],
        finish_reason: 'tool_calls'
      },
      { assistant_text: 'Merhaba, tale', tool_calls: [], finish_reason: 'length' },
      {
        assistant_text: 'Düşük bütçe önceliğiniz için 2.500 TRY fiyatlı Menteşeli Kapı Sinekliğini öneririm.',
        tool_calls: [],
        finish_reason: 'stop'
      }
    )

    result = nil
    expect do
      result = described_class.new(
        ai_agent: ai_agent.reload,
        messages: [{ role: 'user', content: 'Balkon kapısı için düşük bütçeli kedi tüllü sineklik öner' }],
        mode: :test,
        adapter: adapter
      ).perform
    end.to change(AiAgentLlmCall, :count).by(3)

    expect(result[:assistant_message]['content']).to eq(
      'Düşük bütçe önceliğiniz için 2.500 TRY fiyatlı Menteşeli Kapı Sinekliğini öneririm.'
    )
    expect(AiAgentLlmCall.order(:id).last(2).map(&:finish_reason)).to eq(%w[length stop])
    expect(AiAgentLlmCall.last.step).to eq('tool_follow_up_incomplete_retry')
    expect(AiAgentLlmCall.last.request_messages.last['content']).to include('cut off by the output limit')
  end

  it 'uses a larger final retry budget and hands off when it remains truncated' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    hinged_url = 'https://example.test/menteseli-kapi?"RENK"=GRI'
    accordion_url = 'https://example.test/akordiyon-kapi'
    pet_mesh_url = 'https://example.test/kedi-tullu-kapi'
    tool_result = {
      status: 'ok',
      result_type: 'show_candidates',
      result_count: 3,
      candidates: [
        {
          display_name: 'Menteşeli Kapı Sinekliği',
          link: { url: hinged_url },
          price: { reference_amount: 1250, currency: 'TRY', final_total_known: false },
          description: 'Kedi tırmalamasına dayanıklıdır.'
        },
        {
          display_name: 'Akordiyon Kapı Sinekliği',
          link: { url: accordion_url },
          price: { reference_amount: 1500.50, currency: 'TRY', final_total_known: false }
        },
        {
          display_name: 'Kedi Tüllü Kapı Sinekliği',
          link: { url: pet_mesh_url }
        }
      ]
    }
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: {
        'tool' => 'ikas_catalog_search',
        'status' => 'ok',
        'tool_call_id' => 'catalog-1',
        'result' => tool_result.deep_stringify_keys
      },
      tool_result: tool_result
    )
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(
      instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    )
    calls = []
    allow(adapter).to receive(:perform) do |**payload|
      calls << payload
      case calls.length
      when 1
        {
          assistant_text: nil,
          tool_calls: [{
            id: 'catalog-1',
            type: 'function',
            name: 'ikas_catalog_search',
            arguments: { queries: ['balkon kapısı sineklik', 'menteşeli kapı sineklik', 'akordiyon kapı sineklik'] }.to_json
          }],
          finish_reason: 'tool_calls'
        }
      when 2
        {
          assistant_text: nil,
          tool_calls: [{ id: 'catalog-over-budget', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'kedi tüllü kapı' }.to_json }],
          finish_reason: 'tool_calls'
        }
      when 3
        { assistant_text: 'Merhaba! Balkon kapınız için sineklik bakıy', tool_calls: [], finish_reason: 'length' }
      else
        { assistant_text: nil, tool_calls: [], finish_reason: 'length' }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Balkon kapısı için düşük bütçeli bir sineklik önerir misin?' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    retry_log = AiAgentLlmCall.find_by!(conversation: conversation, step: 'tool_final_incomplete_retry')

    expect(calls.third).not_to have_key(:max_tokens)
    expect(calls.fourth[:max_tokens]).to eq(4_096)
    expect(retry_log.response['request_options']).to eq('max_tokens' => 4_096)
    expect(result[:terminal_action]).to eq('handoff')
    expect(result[:assistant_message]['content']).not_to include(
      'Merhaba! Balkon kapınız için sineklik bakıy',
      'Menteşeli Kapı Sinekliği',
      'Akordiyon Kapı Sinekliği',
      'Kedi Tüllü Kapı Sinekliği'
    )
    expect(adapter).to have_received(:perform).exactly(4).times
  end

  it 'hands off after a larger final retry still truncates without safe catalog evidence' do
    allow(adapter).to receive(:perform).and_return(
      { assistant_text: 'Kısmi yan', tool_calls: [], finish_reason: 'length' },
      { assistant_text: nil, tool_calls: [], finish_reason: 'length' }
    )
    orchestrator = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Bir ürün önerir misin?' }],
      mode: :test,
      adapter: adapter
    )
    tool_events = [{
      'tool' => 'ikas_catalog_search',
      'result' => { 'result_type' => 'no_match', 'result_count' => 0, 'candidates' => [] }
    }]

    result = orchestrator.send(:final_answer_result, [], tool_events, 'Reply from the available evidence.')

    expect(result[:terminal_action]).to eq('handoff')
    expect(result[:assistant_message]['content']).not_to include('Kısmi yan')
    expect(adapter).to have_received(:perform).with(hash_including(max_tokens: 4_096)).once
  end

  it 'recovers when a tools-disabled final answer attempts another tool call' do
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [
          {
            id: 'unexpected-catalog-call',
            type: 'function',
            name: 'ikas_catalog_search',
            arguments: { query: 'pencere sinekliği' }.to_json
          }
        ],
        finish_reason: 'tool_calls'
      },
      {
        assistant_text: 'Beyaz 70x90 cm pencere sinekliği için net bir eşleşme bulamadım.',
        tool_calls: [],
        finish_reason: 'stop'
      }
    )
    orchestrator = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Beyaz 70x90 cm pencere sinekliği istiyorum.' }],
      mode: :test,
      adapter: adapter
    )
    tool_events = [{
      'tool' => 'ikas_catalog_search',
      'result' => { 'result_type' => 'no_match', 'result_count' => 0, 'candidates' => [] }
    }]

    result = orchestrator.send(
      :final_answer_result,
      [{ role: 'user', content: 'Beyaz 70x90 cm pencere sinekliği istiyorum.' }],
      tool_events,
      'Reply using the available tool results.'
    )

    expect(result[:terminal_action]).to be_nil
    expect(result[:assistant_message]['content']).to eq(
      'Beyaz 70x90 cm pencere sinekliği için net bir eşleşme bulamadım.'
    )
    expect(adapter).to have_received(:perform).twice
    expect(AiAgentLlmCall.pluck(:step)).to include('customer_facing_finalizer')
  end

  it 'does not return an answer that remains cut off after its retry' do
    allow(adapter).to receive(:perform).and_return(
      { assistant_text: 'Merhaba, tale', tool_calls: [], finish_reason: 'length' },
      { assistant_text: 'Merhaba, iste', tool_calls: [], finish_reason: 'length' }
    )

    result = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Bir ürün önerir misin?' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:terminal_action]).to eq('handoff')
    expect(result[:assistant_message]['content']).not_to include('Merhaba, tale', 'Merhaba, iste')
    expect(adapter).to have_received(:perform).twice
  end

  it 'localizes automatic safety handoff messages to the configured instruction locale' do
    ai_agent.update!(
      config: {
        'instructions' => { 'version' => 4, 'locale' => 'en' },
        'tools' => { 'enabled' => ['human_handoff'] }
      }
    )
    allow(adapter).to receive(:perform).and_return(
      { assistant_text: 'Partial answer', tool_calls: [], finish_reason: 'length' },
      { assistant_text: 'Still partial', tool_calls: [], finish_reason: 'length' }
    )

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Can you recommend a product?' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:terminal_action]).to eq('handoff')
    expect(result[:assistant_message]['content']).to eq('I am transferring you to a team member. Our team will help you.')
    expect(result[:tool_events].last.dig('args', 'customer_message')).to eq(result[:assistant_message]['content'])

    ai_agent.update!(
      config: {
        'instructions' => { 'version' => 4, 'locale' => 'tr' },
        'tools' => { 'enabled' => ['human_handoff'] }
      }
    )
    turkish_result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Bir ürün önerebilir misiniz?' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(turkish_result[:assistant_message]['content']).to eq('Sizi bir temsilciye aktarıyorum. Ekibimiz yardımcı olacak.')
  end

  it 'returns free-form catalog reasoning without evidence finalization' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    hinged_url = 'https://example.test/menteseli-kapi-sineklik'
    accordion_url = 'https://example.test/akordiyon-kapi-sineklik'
    tool_result = {
      status: 'ok',
      result_type: 'multi_search',
      queries: [
        {
          query: 'akordiyon kapı sineklik',
          result_type: 'show_candidates',
          candidates: [
            {
              display_name: 'Akordiyon Kapı Sineklik Antrasit',
              evidence: [],
              price: { reference_amount: 2637.0, currency: 'TRY', final_total_known: false },
              link: { url: accordion_url }
            }
          ]
        },
        {
          query: 'menteşeli kapı sineklik',
          result_type: 'show_candidates',
          candidates: [
            {
              display_name: 'Menteşeli Kapı Sineklik Antrasit',
              evidence: [],
              price: { reference_amount: 1233.84, currency: 'TRY', final_total_known: false },
              link: { url: hinged_url }
            }
          ]
        }
      ]
    }
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: {
        'tool' => 'ikas_catalog_search',
        'status' => 'ok',
        'tool_call_id' => 'catalog-physical-claims',
        'result' => tool_result.deep_stringify_keys
      },
      tool_result: tool_result
    )
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(
      instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    )
    physical_reasoning = 'Menteşeli modeller sert çerçeveli olduğu için kedi tırmalasa da ezilmez, ' \
                         'akordiyon/pileli modeller ise kedi tırmanırsa sarkabilir veya hasar görebilir.'
    free_form_answer = "Menteşeli kapı sinekliği kediniz için en uygun seçenektir. #{physical_reasoning}"
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
        {
          assistant_text: nil,
          tool_calls: [
            {
              id: 'catalog-physical-claims',
              type: 'function',
              name: 'ikas_catalog_search',
              arguments: { queries: ['akordiyon kapı sineklik', 'menteşeli kapı sineklik'] }.to_json
            }
          ],
          finish_reason: 'tool_calls'
        }
      elsif calls.length == 2
        { assistant_text: free_form_answer, tool_calls: [], finish_reason: 'stop' }
      else
        raise 'catalog reasoning should not invoke evidence finalization'
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Kedim için menteşeli mi akordiyon mu önerirsin?' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to eq(free_form_answer)
    expect(result[:terminal_action]).to be_nil
    expect(result[:tool_events].map { |event| event['tool'] }).to eq(['ikas_catalog_search'])
    expect(adapter).to have_received(:perform).twice
    expect(AiAgentLlmCall.pluck(:step)).not_to include('customer_facing_finalizer', 'customer_facing_finalizer_retry')
  end

  it 'passes compact catalog context to the model while retaining the complete tool event' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    candidates = Array.new(12) do |index|
      {
        item_id: "item-#{index}",
        product_id: "product-#{index}",
        display_name: "Product #{index}",
        relevance_score: 50 - index,
        relevance_signals: [{ kind: 'fts_bm25_match', score: 10 }],
        link: { url: "https://example.test/products/#{index}" }
      }
    end
    tool_result = { status: 'ok', result_type: 'show_candidates', result_count: 12, candidates: candidates }
    tool_execution = AiAgents::ToolExecutor::Result.new(
      status: 'executed',
      tool_event: {
        'tool' => 'ikas_catalog_search',
        'status' => 'ok',
        'tool_call_id' => 'catalog-compact',
        'result' => tool_result.deep_stringify_keys
      },
      tool_result: tool_result
    )
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(
      instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    )
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      if calls.one?
        {
          assistant_text: nil,
          tool_calls: [{ id: 'catalog-compact', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'door screen' }.to_json }],
          finish_reason: 'tool_calls'
        }
      else
        { assistant_text: 'Product 0 is a concise option.', tool_calls: [], finish_reason: 'stop' }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Show me a door screen.' }],
      mode: :test,
      adapter: adapter
    ).perform

    model_result = JSON.parse(calls.second[:messages].find { |message| message[:role] == 'tool' }.fetch(:content))
    expect(model_result.fetch('candidates').size).to eq(8)
    expect(model_result.fetch('candidates_omitted')).to eq(4)
    expect(model_result.fetch('candidates').first).not_to include('relevance_score', 'relevance_signals')
    expect(result.dig(:tool_events, 0, 'result', 'candidates').size).to eq(12)
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

  it 'applies structural URL safety before persisting a live terminal tool message' do
    allow(adapter).to receive(:perform).and_return({
      assistant_text: nil,
      tool_calls: [{
        id: 'call_1',
        type: 'function',
        name: 'human_handoff',
        arguments: {
          reason: 'Need help',
          customer_message: 'Continue at [this page](https://invented.example.test/path).',
          internal_note: 'Escalate',
          labels: ['vip']
        }.to_json
      }],
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

    expect(result[:assistant_message]['content']).to eq('Continue at this page.')
    expect(conversation.messages.outgoing.where(private: false, sender: ai_agent.agent_bot).last.content).to eq('Continue at this page.')
  end

  it 'replaces internal protocol markup before persisting a live terminal tool message' do
    allow(adapter).to receive(:perform).and_return({
      assistant_text: nil,
      tool_calls: [{
        id: 'call_1',
        type: 'function',
        name: 'human_handoff',
        arguments: {
          reason: 'Need help',
          customer_message: '<tool_calls>human_handoff</tool_calls>',
          internal_note: 'Escalate',
          labels: ['vip']
        }.to_json
      }],
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

    expected_message = 'I am transferring you to a team member. Our team will help you.'
    expect(result[:assistant_message]['content']).to eq(expected_message)
    expect(conversation.messages.outgoing.where(private: false, sender: ai_agent.agent_bot).last.content).to eq(expected_message)
  end

  it 'returns a terminal option presentation in test mode' do
    allow(adapter).to receive(:perform).and_return({
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
    })

    result = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Yardıma ihtiyacım var' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:terminal_action]).to eq('present_options')
    expect(result[:assistant_message]['content']).to eq('Nasıl devam edelim?')
    expect(result[:assistant_message].dig('tool_result', 'presentation', 'content_type')).to eq('input_select')
    expect(result[:assistant_message].dig('tool_result', 'presentation', 'items').pluck('title')).to eq(['Ürün seçimi', 'Sipariş desteği'])
    expect(result[:assistant_message]['turn_telemetry']['final_answer_source']).to eq('tool_presentation')
  end

  it 'ends the turn with a catalog product presentation after a successful catalog search' do
    ai_agent.update!(
      config: {
        'tools' => {
          'enabled' => %w[ikas_catalog_search present_catalog_products],
          'present_catalog_products' => { 'enabled' => true }
        }
      }
    )
    allow(tool_availability).to receive(:available_keys).and_return(%w[ikas_catalog_search present_catalog_products])
    catalog_result = {
      status: 'ok',
      result_type: 'show_candidates',
      candidates: [{ item_id: 'variant:red', display_name: 'Kırmızı Sineklik', image: { available: true, count: 1 } }]
    }
    presentation_result = {
      status: 'ok',
      terminal_action: 'present_catalog_products',
      customer_message: 'Balkon kapınız için uygun ürünümüz aşağıda.',
      presentation: {
        id: 'presentation-1',
        content_type: 'catalog_products',
        mode: 'products',
        items: [{ item_id: 'variant:red', display_name: 'Kırmızı Sineklik', images: ['https://cdn.myikas.com/red.webp'] }]
      }
    }
    executor = instance_double(AiAgents::ToolExecutor)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    allow(executor).to receive(:execute) do |tool_call|
      result = tool_call[:name] == 'ikas_catalog_search' ? catalog_result : presentation_result
      AiAgents::ToolExecutor::Result.new(
        status: 'executed',
        tool_event: {
          'tool' => tool_call[:name],
          'status' => 'ok',
          'tool_call_id' => tool_call[:id],
          'result' => result.deep_stringify_keys
        },
        tool_result: result
      )
    end
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [{ id: 'catalog-1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'kırmızı sineklik' }.to_json }],
        finish_reason: 'tool_calls'
      },
      {
        assistant_text: nil,
        tool_calls: [{
          id: 'images-1',
          type: 'function',
          name: 'present_catalog_products',
          arguments: {
            mode: 'products',
            catalog_item_ids: ['variant:red'],
            customer_message: 'Balkon kapınız için uygun ürünümüz aşağıda.'
          }.to_json
        }],
        finish_reason: 'tool_calls'
      }
    )

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Kırmızı balkon sinekliğinin görselini göster' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:terminal_action]).to eq('present_catalog_products')
    expect(result[:assistant_message]['content']).to eq('Balkon kapınız için uygun ürünümüz aşağıda.')
    expect(result[:assistant_message].dig('tool_result', 'presentation', 'items', 0, 'display_name')).to eq('Kırmızı Sineklik')
    expect(result[:tool_events].pluck('tool')).to eq(%w[ikas_catalog_search present_catalog_products])
    expect(adapter).to have_received(:perform).twice
  end

  it 'omits option presentation and its prompt rules when the merchant disables it' do
    ai_agent.update!(config: {
                       'tools' => {
                         'enabled' => ['human_handoff'],
                         'present_options' => { 'enabled' => false }
                       }
                     })
    allow(adapter).to receive(:perform).and_return({ assistant_text: 'How can I help?', tool_calls: [], finish_reason: 'stop' })

    described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Hi' }],
      mode: :test,
      adapter: adapter
    ).perform

    request = AiAgentLlmCall.last
    expect(request.request_tool_names).not_to include('present_options')
    expect(request.request_messages.first['content']).not_to include('Customer option rules:', '`present_options`')
  end

  it 'falls back to a plain question when option presentation is invalid' do
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [
          {
            id: 'options-1',
            type: 'function',
            name: 'present_options',
            arguments: { question: 'Hangisi?', options: [{ label: 'Only one' }] }.to_json
          }
        ],
        finish_reason: 'tool_calls'
      },
      { assistant_text: 'Hangi konuda destek istersiniz?', tool_calls: [], finish_reason: 'stop' }
    )

    result = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Yardım' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:terminal_action]).to be_nil
    expect(result[:assistant_message]['content']).to eq('Hangi konuda destek istersiniz?')
    expect(result[:tool_events].last).to include('tool' => 'present_options', 'status' => 'error')
    expect(result[:tool_events].none? { |event| event['tool'] == 'human_handoff' }).to be(true)
  end

  it 'defers option presentation when the model requests evidence and presentation together' do
    orchestrator = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Renkler?' }],
      mode: :test,
      adapter: adapter
    )
    catalog_call = { id: 'catalog-1', name: 'ikas_catalog_search', arguments: { query: 'sineklik renk' }.to_json }
    options_call = { id: 'options-1', name: 'present_options', arguments: { question: 'Renk?', catalog_option_ids: %w[a b] }.to_json }

    expect(orchestrator.send(:tool_calls_to_execute, [options_call, catalog_call])).to eq([catalog_call])
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
    expect(adapter).to have_received(:perform).exactly(2).times
  end

  it 'returns the model response for a catalog no_match as a normal search outcome' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    tool_result = { status: 'ok', result_type: 'no_match', query: 'purple unicorn screen', result_count: 0, candidates: [] }
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
          tool_calls: [{ id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'purple unicorn screen' }.to_json }],
          finish_reason: 'tool_calls'
        }
      else
        { assistant_text: 'I could not find that product. Would you like a different screen type?', tool_calls: [], finish_reason: 'stop' }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Do you have a purple unicorn screen?' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to eq('I could not find that product. Would you like a different screen type?')
    expect(result[:assistant_message]['turn_telemetry']).to include(
      'catalog_search_units_used' => 1,
      'handoff_used' => false,
      'final_answer_source' => 'tool_context'
    )
    expect(adapter).to have_received(:perform).exactly(2).times
    expect(AiAgentLlmCall.pluck(:step)).not_to include('customer_facing_finalizer')
  end

  it 'returns one unknown tool call to the model for an exact-name correction' do
    account.enable_features('ikas_integration')
    account.save!
    connection_status = instance_double(Integrations::Ikas::ConnectionStatus, payload: { state: 'connected' })
    allow(Integrations::Ikas::ConnectionStatus).to receive(:new).with(account: account).and_return(connection_status)
    ai_agent.update!(config: { 'tools' => { 'enabled' => %w[human_handoff ikas_catalog_search] } })
    api_inbox = create(:inbox, account: account, channel: create(:channel_api, account: account))
    api_conversation = create(:conversation, account: account, inbox: api_inbox)
    api_trigger_message = create(
      :message,
      account: account,
      inbox: api_inbox,
      conversation: api_conversation,
      message_type: 'incoming',
      sender: api_conversation.contact
    )
    initial_result = { status: 'ok', result_type: 'no_match', query: 'balkon kapısı sineklik', result_count: 0, candidates: [] }
    corrected_result = {
      status: 'ok',
      result_type: 'show_candidates',
      query: 'kapı sineklik',
      result_count: 1,
      candidates: [
        {
          display_name: 'Menteşeli Kapı Sineklik',
          link: { url: 'https://example.test/menteseli-kapi-sineklik' }
        }
      ]
    }
    catalog_requests = []
    catalog_service = instance_double(AiAgents::Tools::IkasCatalogSearchService)
    allow(catalog_service).to receive(:call) do |args:|
      catalog_requests << args
      [initial_result, corrected_result].fetch(catalog_requests.length - 1)
    end
    allow(AiAgents::Tools::IkasCatalogSearchService).to receive(:new).and_return(catalog_service)
    calls = []
    responses = [
      {
        assistant_text: nil,
        tool_calls: [
          { id: 'catalog-initial', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'balkon kapısı sineklik' }.to_json }
        ],
        finish_reason: 'tool_calls'
      },
      {
        assistant_text: nil,
        tool_calls: [
          { id: 'catalog-typo', type: 'function', name: 'iks_catalog_search', arguments: { query: 'kapı sineklik' }.to_json }
        ],
        finish_reason: 'tool_calls'
      },
      {
        assistant_text: nil,
        tool_calls: [
          { id: 'catalog-corrected', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'kapı sineklik' }.to_json }
        ],
        finish_reason: 'tool_calls'
      },
      {
        assistant_text: 'Menteşeli Kapı Sinekliği buldum: https://example.test/menteseli-kapi-sineklik',
        tool_calls: [],
        finish_reason: 'stop'
      }
    ]
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      responses.fetch(calls.length - 1)
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Balkon kapısı için sineklik önerir misin?' }],
      mode: :live,
      conversation: api_conversation,
      trigger_message: api_trigger_message,
      adapter: adapter
    ).perform

    correction_message = calls.third.fetch(:messages).find do |message|
      message[:role] == 'tool' && message[:tool_call_id] == 'catalog-typo'
    end
    correction_feedback = JSON.parse(correction_message.fetch(:content))

    expect(correction_feedback).to include(
      'status' => 'error',
      'error_code' => 'unknown_tool',
      'recoverable' => true,
      'requested_tool_name' => 'iks_catalog_search',
      'available_tool_names' => %w[human_handoff ikas_catalog_search]
    )
    expected_catalog_requests = [
      { 'query' => 'balkon kapısı sineklik' },
      { 'query' => 'kapı sineklik' }
    ]
    expected_executions = [
      ['ikas_catalog_search', 'executed', nil],
      %w[iks_catalog_search rejected unknown_tool],
      ['ikas_catalog_search', 'executed', nil]
    ]

    expect(catalog_requests).to eq(expected_catalog_requests)
    expect(AiAgentToolExecution.where(conversation: api_conversation).order(:id).pluck(:tool_key, :status, :error_code)).to eq(expected_executions)
    expect(result[:terminal_action]).to be_nil
    expect(result[:assistant_message]['content']).to include('Menteşeli Kapı Sinekliği')
    expect(result[:tool_events].map { |event| event['tool'] }).to eq(
      %w[ikas_catalog_search iks_catalog_search ikas_catalog_search]
    )
    expect(result[:tool_events].none? { |event| event['tool'] == 'human_handoff' }).to be(true)
    expect(adapter).to have_received(:perform).exactly(4).times
  end

  it 'fails closed after the model repeats an unknown tool call' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => %w[human_handoff ikas_catalog_search] } })
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [{ id: 'typo-1', type: 'function', name: 'iks_catalog_search', arguments: '{}' }],
        finish_reason: 'tool_calls'
      },
      {
        assistant_text: nil,
        tool_calls: [{ id: 'typo-2', type: 'function', name: 'iks_catalog_search', arguments: '{}' }],
        finish_reason: 'tool_calls'
      }
    )

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Balkon kapısı için sineklik önerir misin?' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    expect(result[:terminal_action]).to eq('handoff')
    expect(result[:tool_events].map { |event| event['tool'] }).to eq(
      %w[iks_catalog_search iks_catalog_search human_handoff]
    )
    expected_executions = [
      %w[iks_catalog_search rejected unknown_tool],
      %w[iks_catalog_search rejected unknown_tool],
      ['human_handoff', 'executed', nil]
    ]
    expect(AiAgentToolExecution.where(conversation: conversation).order(:id).pluck(:tool_key, :status, :error_code)).to eq(expected_executions)
    expect(adapter).to have_received(:perform).twice
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
          assistant_text: '<tool_calls>ikas_catalog_search</tool_calls>',
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
      'final_answer_source' => 'tool_context'
    )
    expect(result[:tool_events].map { |event| event['tool'] }).to eq(['ikas_catalog_search'])
    expect(adapter).to have_received(:perform).exactly(4).times
    expect(AiAgentLlmCall.pluck(:step)).to include('customer_facing_finalizer_retry')
  end

  it 'preserves an order answer when a catalog search has no match in the same turn' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => %w[ikas_catalog_search ikas_lookup_order] } })
    catalog_result = { status: 'ok', result_type: 'no_match', result_count: 0, candidates: [] }
    order_result = { status: 'ok', result_type: 'match', order: { order_number: 'ORD-42', status: 'shipped' } }
    executions = [
      AiAgents::ToolExecutor::Result.new(
        status: 'executed',
        tool_event: { 'tool' => 'ikas_catalog_search', 'status' => 'ok', 'result' => catalog_result.deep_stringify_keys },
        tool_result: catalog_result
      ),
      AiAgents::ToolExecutor::Result.new(
        status: 'executed',
        tool_event: { 'tool' => 'ikas_lookup_order', 'status' => 'ok', 'result' => order_result.deep_stringify_keys },
        tool_result: order_result
      )
    ]
    executor = instance_double(AiAgents::ToolExecutor)
    allow(executor).to receive(:execute).and_return(*executions)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [
          { id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'mor perde' }.to_json },
          { id: 'call_2', type: 'function', name: 'ikas_lookup_order', arguments: { order_number: 'ORD-42' }.to_json }
        ],
        finish_reason: 'tool_calls'
      },
      { assistant_text: 'Mor perdeyi bulamadım. ORD-42 siparişiniz kargoya verildi.', tool_calls: [], finish_reason: 'stop' }
    )

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Mor perde var mı, ORD-42 ne durumda?' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to include('ORD-42 siparişiniz kargoya verildi')
    expect(adapter).to have_received(:perform).twice
  end

  it 'preserves multiple catalog no-match results for the model response' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    result_one = { status: 'ok', result_type: 'no_match', result_count: 0, candidates: [], query: 'mor perde' }
    result_two = { status: 'ok', result_type: 'no_match', result_count: 0, candidates: [], query: 'yeşil sineklik' }
    executions = [result_one, result_two].map.with_index do |tool_result, index|
      AiAgents::ToolExecutor::Result.new(
        status: 'executed',
        tool_event: {
          'tool' => 'ikas_catalog_search',
          'status' => 'ok',
          'tool_call_id' => "call_#{index + 1}",
          'result' => tool_result.deep_stringify_keys
        },
        tool_result: tool_result
      )
    end
    executor = instance_double(AiAgents::ToolExecutor)
    allow(executor).to receive(:execute).and_return(*executions)
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(executor)
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [
          { id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'mor perde' }.to_json },
          { id: 'call_2', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'yeşil sineklik' }.to_json }
        ],
        finish_reason: 'tool_calls'
      },
      { assistant_text: 'Mor perdeyi de yeşil sinekliği de bulamadım.', tool_calls: [], finish_reason: 'stop' }
    )

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Mor perde ve yeşil sineklik var mı?' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to eq('Mor perdeyi de yeşil sinekliği de bulamadım.')
    expect(adapter).to have_received(:perform).twice
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
        { assistant_text: '<tool_calls>ikas_catalog_search</tool_calls>', tool_calls: [], finish_reason: 'stop' }
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

  it 'returns ordinary catalog prose without semantic phrase filtering' do
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
        raise 'ordinary catalog prose should not invoke customer-facing regeneration'
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

    expect(result[:assistant_message]['content']).to eq(
      'Elimdeki 3 arama sonucuna göre KEDİ Tüllü Akordeon Kapı Sineklik uygun görünüyor.'
    )
    expect(adapter).to have_received(:perform).twice
    expect(AiAgentLlmCall.pluck(:step)).not_to include('customer_facing_finalizer')
  end

  it 'repairs a truncated trailing markdown link from exact catalog evidence' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })
    product_url = 'https://example.test/kedi-sineklik?%22RENK%22=ANTRAS%C4%B0T'
    tool_result = {
      status: 'ok',
      result_type: 'show_candidates',
      candidates: [{ display_name: 'Kedi Sineklik Antrasit', link: { url: product_url } }]
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
    allow(AiAgents::ToolExecutor).to receive(:new).and_return(
      instance_double(AiAgents::ToolExecutor, execute: tool_execution)
    )
    allow(adapter).to receive(:perform).and_return(
      {
        assistant_text: nil,
        tool_calls: [
          { id: 'call_1', type: 'function', name: 'ikas_catalog_search', arguments: { query: 'antrasit kedi sineklik' }.to_json }
        ],
        finish_reason: 'tool_calls'
      },
      {
        assistant_text: 'Kedi Sineklik Antrasit: [Ürüne git](https://example.test/kedi-sineklik?%22RENK%22=AN',
        tool_calls: [],
        finish_reason: 'stop'
      }
    )

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Antrasit kedi sinekliği önerir misin?' }],
      mode: :test,
      adapter: adapter
    ).perform

    expect(result[:assistant_message]['content']).to end_with("[Ürüne git](#{product_url})")
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

  it 'executes the ordered catalog queries that fit the remaining query budget' do
    account.enable_features('ikas_integration')
    account.save!
    connection_status = instance_double(Integrations::Ikas::ConnectionStatus, payload: { state: 'connected' })
    allow(Integrations::Ikas::ConnectionStatus).to receive(:new).with(account: account).and_return(connection_status)
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'] } })

    initial_result = {
      status: 'ok',
      query: 'balkon kapısı sineklik',
      result_type: 'show_candidates',
      result_count: 3,
      candidates: [
        { display_name: 'Akordeon Kapı Sineklik Altınmeşe' },
        { display_name: 'Akordeon Kapı Sineklik Antrasit' },
        { display_name: 'Akordeon Kapı Sineklik Beyaz' }
      ]
    }
    follow_up_result = {
      status: 'ok',
      result_type: 'multi_search',
      result_count: 1,
      queries: [
        {
          status: 'ok',
          query: 'menteşeli kapı sineklik',
          result_type: 'show_candidates',
          result_count: 1,
          candidates: [{ display_name: 'Menteşeli Kapı Sineklik Antrasit' }]
        },
        {
          status: 'ok',
          query: 'balkon sineklik kedi',
          result_type: 'no_match',
          result_count: 0,
          candidates: []
        }
      ]
    }
    catalog_requests = []
    catalog_service = instance_double(AiAgents::Tools::IkasCatalogSearchService)
    allow(catalog_service).to receive(:call) do |args:|
      catalog_requests << args
      [initial_result, follow_up_result].fetch(catalog_requests.length - 1)
    end
    allow(AiAgents::Tools::IkasCatalogSearchService).to receive(:new).and_return(catalog_service)

    free_form_answer = 'Menteşeli modeller daha dayanıklıdır; akordiyon modeller açılıp kapanma kolaylığı sağlar.'
    calls = []
    allow(adapter).to receive(:perform) do |payload|
      calls << payload
      case calls.length
      when 1
        {
          assistant_text: nil,
          tool_calls: [
            {
              id: 'catalog-initial',
              type: 'function',
              name: 'ikas_catalog_search',
              arguments: { query: 'balkon kapısı sineklik' }.to_json
            }
          ],
          finish_reason: 'tool_calls'
        }
      when 2
        {
          assistant_text: nil,
          tool_calls: [
            {
              id: 'catalog-follow-up',
              type: 'function',
              name: 'ikas_catalog_search',
              arguments: {
                queries: ['menteşeli kapı sineklik', 'balkon sineklik kedi', 'akordiyon sineklik kapı']
              }.to_json
            }
          ],
          finish_reason: 'tool_calls'
        }
      else
        { assistant_text: free_form_answer, tool_calls: [], finish_reason: 'stop' }
      end
    end

    result = described_class.new(
      ai_agent: ai_agent.reload,
      messages: [{ role: 'user', content: 'Balkon kapısı için akordiyon mu menteşeli mi? Kedim var; ikisini de göster.' }],
      mode: :live,
      conversation: conversation,
      trigger_message: trigger_message,
      adapter: adapter
    ).perform

    retained_queries = ['menteşeli kapı sineklik', 'balkon sineklik kedi']
    expected_requests = [
      { 'query' => 'balkon kapısı sineklik' },
      { 'queries' => retained_queries }
    ]
    persisted_arguments = AiAgentToolExecution.where(conversation: conversation, tool_key: 'ikas_catalog_search').order(:id).pluck(:arguments)

    expect(catalog_requests).to eq(expected_requests)
    expect(persisted_arguments).to eq(expected_requests)
    expect(result[:tool_events].map { |event| event['tool'] }).to eq(%w[ikas_catalog_search ikas_catalog_search])
    expect(result[:assistant_message]['content']).to eq(free_form_answer)
    expect(result[:assistant_message]['turn_telemetry']).to include(
      'catalog_search_units_used' => 3,
      'catalog_search_queries_truncated' => 1
    )
    expect(catalog_requests.flat_map { |request| request['queries'] || request['query'] }).to eq(
      ['balkon kapısı sineklik', *retained_queries]
    )
    expect(adapter).to have_received(:perform).exactly(3).times
  end

  it 'counts case and Turkish-diacritic variants as one catalog query unit' do
    orchestrator = described_class.new(
      ai_agent: ai_agent,
      messages: [{ role: 'user', content: 'Yatak seçeneklerini göster.' }],
      mode: :test,
      adapter: adapter
    )
    tool_call = {
      name: 'ikas_catalog_search',
      arguments: { queries: %w[Yatak yatak YATAK SİNEKLİK sineklik] }.to_json
    }

    expect(orchestrator.send(:catalog_search_query_units, tool_call)).to eq(2)
    retained = orchestrator.send(:catalog_search_tool_call_with_query_limit, tool_call, 1)
    expect(JSON.parse(retained[:arguments])['queries']).to eq(['Yatak'])
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
