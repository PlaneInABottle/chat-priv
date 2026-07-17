require 'rails_helper'

RSpec.describe AiAgents::ToolExecutor do
  before { Integrations::Hook.name }

  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, :with_human_handoff_tool, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:trigger_message) do
    create(:message, account: account, inbox: conversation.inbox, conversation: conversation, message_type: 'incoming', sender: conversation.contact)
  end
  let(:executor) do
    described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :test,
      context: { conversation: conversation, trigger_message: trigger_message }
    )
  end

  def handoff_args
    { reason: 'Need help', customer_message: 'A human will take over.', internal_note: 'Escalate' }
  end

  def tool_call(name: 'human_handoff', arguments: {})
    { id: 'call_1', name: name, arguments: arguments.to_json }
  end

  def stub_handoff_service(result: nil, error: nil)
    service = instance_double(AiAgents::Tools::HumanHandoffService)
    allow(AiAgents::Tools::HumanHandoffService).to receive(:new).and_return(service)
    return allow(service).to receive(:call).and_raise(error) if error

    allow(service).to receive(:call).and_return(result)
  end

  it 'logs unknown tool rejections' do
    result = executor.execute(tool_call(name: 'unknown_tool'))

    expect(result.status).to eq('rejected')
    expect(AiAgentToolExecution.last).to have_attributes(tool_key: 'unknown_tool', status: 'rejected', error_code: 'unknown_tool')
  end

  it 'logs disabled optional tool rejections' do
    ai_agent.update!(config: { 'tools' => { 'enabled' => [] } })

    result = executor.execute(tool_call(name: 'ikas_catalog_search', arguments: { query: '70x90 sineklik' }))

    expect(result.status).to eq('rejected')
    expect(AiAgentToolExecution.last.error_code).to eq('tool_not_enabled')
  end

  it 'logs invalid JSON arguments as an empty hash' do
    result = executor.execute({ id: 'call_1', name: 'human_handoff', arguments: '{' })

    expect(result.status).to eq('rejected')
    expect(AiAgentToolExecution.last).to have_attributes(error_code: 'invalid_tool_arguments', arguments: {})
  end

  it 'logs successful service execution without changing the tool event shape' do
    result = executor.execute(tool_call(arguments: handoff_args))

    expect(result.status).to eq('executed')
    expect(result.tool_event.keys).to match_array(%w[tool status tool_call_id terminal args result])
    expect(AiAgentToolExecution.last).to have_attributes(status: 'executed', tool_key: 'human_handoff')
  end

  it 'implicitly enables knowledge search only when runtime sources are present' do
    knowledge_executor = described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :test,
      context: {
        knowledge_sources: [
          { id: 9, name: 'Returns', content: 'Returns are accepted within 14 days.' }
        ]
      }
    )

    result = knowledge_executor.execute(
      tool_call(name: 'search_knowledge', arguments: { query: 'returns within 14 days' })
    )

    expect(result.status).to eq('executed')
    expect(result.tool_result[:attributions]).to eq([{ source_id: 9, source_name: 'Returns' }])
    expect(AiAgentToolExecution.last).to have_attributes(status: 'executed', tool_key: 'search_knowledge')
  end

  it 'implicitly enables option presentation in test mode and logs the structured result' do
    result = executor.execute(
      tool_call(
        name: 'present_options',
        arguments: { question: 'Choose one', options: [{ label: 'Sales' }, { label: 'Support' }] }
      )
    )

    expect(result.status).to eq('executed')
    expect(result.tool_result).to include(status: 'ok', terminal_action: 'present_options')
    expect(AiAgentToolExecution.last).to have_attributes(status: 'executed', tool_key: 'present_options')
  end

  it 'logs test conversation tool executions without a live conversation link' do
    test_conversation = create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent)
    test_executor = described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :test,
      context: { conversation: test_conversation }
    )

    result = test_executor.execute(tool_call(arguments: handoff_args))

    expect(result.status).to eq('executed')
    expect(AiAgentToolExecution.last).to have_attributes(
      status: 'executed',
      mode: 'test',
      tool_key: 'human_handoff',
      conversation_id: nil,
      message_id: nil
    )
  end

  it 'logs service error results' do
    stub_handoff_service(result: { status: 'error', error_code: 'handoff_failed', raw_response: 'secret' })

    result = executor.execute(tool_call(arguments: handoff_args))

    expect(result.status).to eq('error')
    expect(AiAgentToolExecution.last).to have_attributes(status: 'error', error_code: 'handoff_failed',
                                                         result: { 'status' => 'error', 'error_code' => 'handoff_failed' })
  end

  it 'logs service exceptions as rejected tool exceptions' do
    stub_handoff_service(error: StandardError.new('boom'))

    result = executor.execute(tool_call(arguments: handoff_args))

    expect(result.status).to eq('rejected')
    expect(AiAgentToolExecution.last).to have_attributes(status: 'rejected', error_code: 'tool_exception')
  end

  it 'does not change executor results when logging fails' do
    allow(AiAgentToolExecution).to receive(:create!).and_raise(StandardError, 'log failed')

    result = executor.execute(tool_call(arguments: handoff_args))

    expect(result.status).to eq('executed')
  end

  it 'rejects ikas catalog search when ikas is not connected' do
    account.enable_features('ikas_integration')
    account.save!
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'], 'ikas_catalog_search' => {} } })

    result = executor.execute(tool_call(name: 'ikas_catalog_search', arguments: { query: '70x90 sineklik' }))

    expect(result.status).to eq('rejected')
    expect(AiAgentToolExecution.last.error_code).to eq('ikas_not_connected')
  end

  it 'executes ikas catalog search when ikas is connected' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    account.enable_features('ikas_integration')
    account.save!
    create(:integrations_hook, :ikas, account: account)
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'], 'ikas_catalog_search' => {} } })
    full_result = {
      status: 'ok',
      result_type: 'show_candidates',
      candidates: Array.new(10) { |index| { display_name: "Product #{index}", relevance_score: index } }
    }
    service = instance_double(AiAgents::Tools::IkasCatalogSearchService, call: full_result)
    allow(AiAgents::Tools::IkasCatalogSearchService).to receive(:new).and_return(service)

    result = executor.execute(tool_call(name: 'ikas_catalog_search', arguments: { query: '70x90 sineklik' }))

    expect(result.status).to eq('executed')
    expect(AiAgentToolExecution.last.tool_key).to eq('ikas_catalog_search')
    expect(AiAgentToolExecution.last.result.fetch('candidates').size).to eq(10)
    expect(AiAgentToolExecution.last.result.dig('candidates', 0, 'relevance_score')).to eq(0)
  end

  it 'allows repeated ikas catalog searches in one orchestrated turn' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    account.enable_features('ikas_integration')
    account.save!
    create(:integrations_hook, :ikas, account: account)
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['ikas_catalog_search'], 'ikas_catalog_search' => {} } })
    service = instance_double(AiAgents::Tools::IkasCatalogSearchService, call: { status: 'ok', result_type: 'show_candidates' })
    allow(AiAgents::Tools::IkasCatalogSearchService).to receive(:new).and_return(service)
    repeated_executor = described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :test,
      executed_tool_keys: Set.new(['ikas_catalog_search']),
      context: { conversation: conversation, trigger_message: trigger_message }
    )

    result = repeated_executor.execute(tool_call(name: 'ikas_catalog_search', arguments: { query: 'perde' }))

    expect(result.status).to eq('executed')
    expect(AiAgentToolExecution.last).to have_attributes(status: 'executed', tool_key: 'ikas_catalog_search')
  end

  it 'executes ikas order lookup when ikas is connected and masks contact identifiers in logs' do
    allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    account.enable_features('ikas_integration')
    account.save!
    create(:integrations_hook, :ikas, account: account)
    ai_agent.update!(
      config: {
        'tools' => {
          'enabled' => ['ikas_lookup_order'],
          'ikas_lookup_order' => { 'enabled' => true }
        }
      }
    )
    service = instance_double(AiAgents::Tools::IkasLookupOrderService, call: { status: 'ok', result_type: 'show_order_status' })
    allow(AiAgents::Tools::IkasLookupOrderService).to receive(:new).and_return(service)

    result = executor.execute(
      tool_call(
        name: 'ikas_lookup_order',
        arguments: { order_identifier: '30564', email: 'buyer@example.com', phone: '+905419719978' }
      )
    )

    expect(result.status).to eq('executed')
    expect(result.tool_event['args']).to include('email' => 'b***@example.com', 'phone' => '***9978')
    expect(AiAgentToolExecution.last).to have_attributes(
      tool_key: 'ikas_lookup_order',
      arguments: include('email' => 'b***@example.com', 'phone' => '***9978')
    )
  end
end
