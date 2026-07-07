require 'rails_helper'

RSpec.describe AiAgents::Tools::IkasCatalogSearchService do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }

  def service_double(result)
    instance_double(Integrations::Ikas::CatalogSearchService).tap do |service|
      allow(service).to receive(:call).and_return(result)
    end
  end

  it 'delegates to the account-scoped catalog search service' do
    search_service = instance_double(Integrations::Ikas::CatalogSearchService)
    allow(Integrations::Ikas::CatalogSearchService).to receive(:new).and_return(search_service)
    allow(search_service).to receive(:call).and_return(status: 'ok', result_type: 'show_candidates')

    result = described_class.new(ai_agent: ai_agent, account: account, mode: :test, settings: {}).call(
      args: { 'query' => '70x90 sineklik', 'limit' => 8 }
    )

    expect(result).to eq(status: 'ok', result_type: 'show_candidates')
    expect(Integrations::Ikas::CatalogSearchService).to have_received(:new).with(
      account: account,
      query_text: '70x90 sineklik',
      context_query_text: nil,
      limit: 8
    )
  end

  it 'normalizes, de-duplicates, and caps batch queries' do
    sineklik_service = service_double(status: 'ok', query: 'sineklik', result_type: 'show_candidates', result_count: 1, candidates: [])
    perde_service = service_double(status: 'ok', query: 'perde', result_type: 'show_candidates', result_count: 2, candidates: [])
    stor_service = service_double(status: 'ok', query: 'stor', result_type: 'show_candidates', result_count: 3, candidates: [])

    expect(Integrations::Ikas::CatalogSearchService).to receive(:new).with(
      account: account,
      query_text: 'sineklik',
      context_query_text: nil,
      limit: 4
    ).ordered.and_return(sineklik_service)
    expect(Integrations::Ikas::CatalogSearchService).to receive(:new).with(
      account: account,
      query_text: 'perde',
      context_query_text: nil,
      limit: 4
    ).ordered.and_return(perde_service)
    expect(Integrations::Ikas::CatalogSearchService).to receive(:new).with(
      account: account,
      query_text: 'stor',
      context_query_text: nil,
      limit: 4
    ).ordered.and_return(stor_service)

    result = described_class.new(ai_agent: ai_agent, account: account, mode: :test, settings: {}).call(
      args: { 'queries' => [' sineklik ', '', 'perde', 'sineklik', 'stor', 'jaluzi'], 'limit' => 4 }
    )

    expect(result).to include(status: 'ok', result_type: 'multi_search', result_count: 6)
    expect(result[:queries].pluck(:query)).to eq(%w[sineklik perde stor])
  end

  it 'returns invalid_query when no valid query remains' do
    expect(Integrations::Ikas::CatalogSearchService).not_to receive(:new)

    result = described_class.new(ai_agent: ai_agent, account: account, mode: :test, settings: {}).call(
      args: { 'queries' => [' ', nil, "\t"] }
    )

    expect(result).to eq(
      status: 'error',
      error_code: 'invalid_query',
      error_message: 'Catalog query cannot be blank.',
      warnings: []
    )
  end

  it 'returns multi_search for a mixed ok and error batch' do
    ok_service = service_double(
      status: 'ok',
      result_type: 'show_candidates',
      candidates: [{ product_id: 'p-sineklik' }, { product_id: 'p-akordiyon' }],
      warnings: ['scope_used'],
      catalog: { store_host: 'store.example.com' }
    )
    error_service = service_double(
      status: 'error',
      error_code: 'catalog_query_failed',
      error_message: 'Ikas catalog search failed.',
      warnings: ['scope_used', 'retry_later']
    )

    expect(Integrations::Ikas::CatalogSearchService).to receive(:new).with(
      account: account,
      query_text: 'sineklik',
      context_query_text: nil,
      limit: 8
    ).ordered.and_return(ok_service)
    expect(Integrations::Ikas::CatalogSearchService).to receive(:new).with(
      account: account,
      query_text: 'perde',
      context_query_text: nil,
      limit: 8
    ).ordered.and_return(error_service)

    result = described_class.new(ai_agent: ai_agent, account: account, mode: :test, settings: {}).call(
      args: { 'queries' => %w[sineklik perde], 'limit' => 8 }
    )

    expect(result).to include(status: 'ok', result_type: 'multi_search', result_count: 2, warnings: %w[scope_used retry_later])
    expect(result[:queries].first).to include(query: 'sineklik', status: 'ok', result_count: 2, catalog: { store_host: 'store.example.com' })
    expect(result[:queries].second).to include(query: 'perde', status: 'error', result_count: 0, error_code: 'catalog_query_failed')
  end

  it 'returns error when all batch searches fail' do
    first_service = service_double(status: 'error', error_code: 'catalog_missing', error_message: 'Missing.', warnings: ['one'])
    second_service = service_double(status: 'error', error_code: 'catalog_query_failed', error_message: 'Failed.', warnings: ['one', 'two'])

    expect(Integrations::Ikas::CatalogSearchService).to receive(:new).with(
      account: account,
      query_text: 'sineklik',
      context_query_text: nil,
      limit: 8
    ).ordered.and_return(first_service)
    expect(Integrations::Ikas::CatalogSearchService).to receive(:new).with(
      account: account,
      query_text: 'perde',
      context_query_text: nil,
      limit: 8
    ).ordered.and_return(second_service)

    result = described_class.new(ai_agent: ai_agent, account: account, mode: :test, settings: {}).call(
      args: { 'queries' => %w[sineklik perde], 'limit' => 8 }
    )

    expect(result).to include(
      status: 'error',
      result_type: 'multi_search',
      result_count: 0,
      error_code: 'catalog_multi_search_failed',
      error_message: 'Ikas catalog search failed.',
      warnings: %w[one two]
    )
    expect(result[:queries].pluck(:status)).to eq(%w[error error])
  end

  it 'keeps previous catalog context out of latest-message searches by default' do
    conversation = create(:conversation, account: account)
    create(
      :message,
      account: account,
      conversation: conversation,
      content: 'abi şu beyaz sineklik 90 x 210 var mı detaylı bakalım',
      created_at: 4.minutes.ago
    )
    create(
      :message,
      account: account,
      conversation: conversation,
      content: 'özel not siyah perde 80x180',
      private: true,
      created_at: 3.minutes.ago
    )
    create(
      :message,
      account: account,
      conversation: conversation,
      message_type: 'outgoing',
      content: 'plise perde gri olabilir',
      created_at: 2.minutes.ago
    )
    trigger_message = create(
      :message,
      account: account,
      conversation: conversation,
      content: '70x100',
      created_at: 1.minute.ago
    )
    search_service = instance_double(Integrations::Ikas::CatalogSearchService)
    allow(Integrations::Ikas::CatalogSearchService).to receive(:new).and_return(search_service)
    allow(search_service).to receive(:call).and_return(status: 'ok', result_type: 'show_compatible_candidates')

    described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :live,
      settings: {},
      conversation: conversation,
      trigger_message: trigger_message
    ).call(args: { 'query' => '70x100', 'limit' => 8 })

    expect(Integrations::Ikas::CatalogSearchService).to have_received(:new).with(
      account: account,
      query_text: '70x100',
      context_query_text: nil,
      limit: 8
    )
  end
end
