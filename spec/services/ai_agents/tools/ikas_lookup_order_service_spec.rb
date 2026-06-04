require 'rails_helper'

RSpec.describe AiAgents::Tools::IkasLookupOrderService do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  it 'delegates to the account-scoped ikas order lookup service' do
    lookup_service = instance_double(Integrations::Ikas::OrderLookupService)
    allow(Integrations::Ikas::OrderLookupService).to receive(:new).and_return(lookup_service)
    allow(lookup_service).to receive(:call).and_return(status: 'ok', result_type: 'show_order_status')

    result = described_class.new(
      ai_agent: ai_agent,
      account: account,
      mode: :test,
      settings: {},
      conversation: conversation
    ).call(args: { 'order_identifier' => '30564', 'email' => 'buyer@example.com', 'phone' => '+905419719978', 'limit' => 3 })

    expect(result).to eq(status: 'ok', result_type: 'show_order_status')
    expect(Integrations::Ikas::OrderLookupService).to have_received(:new).with(
      account: account,
      conversation: conversation,
      identifiers: {
        'order_identifier' => '30564',
        'email' => 'buyer@example.com',
        'phone' => '+905419719978'
      },
      limit: 3
    )
  end
end
