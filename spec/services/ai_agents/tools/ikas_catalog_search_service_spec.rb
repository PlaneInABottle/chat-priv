require 'rails_helper'

RSpec.describe AiAgents::Tools::IkasCatalogSearchService do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }

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

  it 'passes recent customer context separately for short follow-up searches' do
    conversation = create(:conversation, account: account)
    create(:message, account: account, conversation: conversation, content: 'sineklik var mi', created_at: 3.minutes.ago)
    create(:message, account: account, conversation: conversation, content: 'akordiyon sineklikler', created_at: 2.minutes.ago)
    trigger_message = create(
      :message,
      account: account,
      conversation: conversation,
      content: '70x100 olsun link ve fiyat verir misin',
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
      context_query_text: ['sineklik var mi', 'akordiyon sineklikler'],
      limit: 8
    )
  end

  it 'does not rewrite complete product searches' do
    conversation = create(:conversation, account: account)
    trigger_message = create(:message, account: account, conversation: conversation, content: '70x100 olsun', created_at: 1.minute.ago)
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
    ).call(args: { 'query' => 'akordiyon sineklik 70x100', 'limit' => 8 })

    expect(Integrations::Ikas::CatalogSearchService).to have_received(:new).with(
      account: account,
      query_text: 'akordiyon sineklik 70x100',
      context_query_text: nil,
      limit: 8
    )
  end

  it 'preserves the latest customer phrase when the tool query drops product descriptors' do
    conversation = create(:conversation, account: account)
    trigger_message = create(:message, account: account, conversation: conversation, content: 'sineklik kasasi ne', created_at: 1.minute.ago)
    search_service = instance_double(Integrations::Ikas::CatalogSearchService)
    allow(Integrations::Ikas::CatalogSearchService).to receive(:new).and_return(search_service)
    allow(search_service).to receive(:call).and_return(status: 'ok', result_type: 'show_candidates')

    described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :live,
      settings: {},
      conversation: conversation,
      trigger_message: trigger_message
    ).call(args: { 'query' => 'sineklik', 'limit' => 8 })

    expect(Integrations::Ikas::CatalogSearchService).to have_received(:new).with(
      account: account,
      query_text: 'sineklik kasasi ne',
      context_query_text: nil,
      limit: 8
    )
  end
end
