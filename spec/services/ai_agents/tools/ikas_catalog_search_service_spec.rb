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
      limit: 8
    )
  end
end
