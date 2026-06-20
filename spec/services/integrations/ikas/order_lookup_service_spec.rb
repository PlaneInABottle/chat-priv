require 'rails_helper'

RSpec.describe Integrations::Ikas::OrderLookupService do
  before do
    Integrations::Hook.name
    allow(Chatwoot).to receive(:encryption_configured?).and_return(true)
    account.enable_features('ikas_integration')
    account.save!
    create(:integrations_hook, :ikas, account: account)
    allow(Integrations::Ikas::AdminApiClient).to receive(:new).and_return(client)
  end

  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, email: nil, phone_number: nil) }
  let(:conversation) { create(:conversation, account: account, contact: contact) }
  let(:client) { instance_double(Integrations::Ikas::AdminApiClient) }

  def order_payload(id:, order_number:, ordered_at: 1_700_000_000_000, tracking: true)
    {
      'id' => id,
      'orderNumber' => order_number,
      'orderedAt' => ordered_at,
      'status' => 'CREATED',
      'orderPackageStatus' => 'FULFILLED',
      'orderPaymentStatus' => 'PAID',
      'totalFinalPrice' => 1299.5,
      'currencyCode' => 'TRY',
      'orderPackages' => [order_package_payload(order_number, tracking: tracking)],
      'orderLineItems' => [order_line_item_payload]
    }
  end

  def order_package_payload(order_number, tracking: true)
    {
      'orderPackageNumber' => "#{order_number}-1",
      'orderPackageFulfillStatus' => 'FULFILLED',
      'trackingInfo' => tracking ? tracking_payload : nil
    }
  end

  def tracking_payload
    {
      'cargoCompany' => 'Yurtiçi Kargo',
      'trackingNumber' => 'TRK123',
      'trackingLink' => 'https://cargo.example.test/TRK123'
    }
  end

  def order_line_item_payload
    {
      'quantity' => 1,
      'variant' => { 'name' => 'Akordeon Pencere Sineklik', 'sku' => 'SKU-1' }
    }
  end

  def order_response(*orders)
    { 'listOrder' => { 'data' => orders } }
  end

  it 'returns a privacy-limited order status for an exact order number' do
    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::LIST_ORDERS, hash_including(orderNumber: { eq: '30564' }))
      .and_return(order_response(order_payload(id: 'order-1', order_number: '30564')))

    result = described_class.new(account: account, conversation: conversation, identifiers: { order_identifier: '30564' }).call

    expect(result).to include(status: 'ok', result_type: 'show_order_status', matched_by: 'order_identifier')
    expect(result[:orders].first).to include(
      order_number: '30564',
      status: 'CREATED',
      payment_status: 'PAID',
      package_status: 'FULFILLED'
    )
    expect(result[:orders].first).not_to include(:customer)
    expect(result[:orders].first[:packages].first[:tracking]).to include(
      cargo_company: 'Yurtiçi Kargo',
      tracking_number: 'TRK123'
    )
  end

  it 'falls back from UUID order number lookup to order ID lookup' do
    order_id = '550e8400-e29b-41d4-a716-446655440000'
    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::LIST_ORDERS, hash_including(orderNumber: { eq: order_id }))
      .and_return(order_response)
    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::LIST_ORDERS, hash_including(id: { eq: order_id }))
      .and_return(order_response(order_payload(id: order_id, order_number: '30564')))

    result = described_class.new(account: account, conversation: conversation, identifiers: { order_identifier: order_id }).call

    expect(result).to include(status: 'ok', result_type: 'show_order_status', matched_by: 'order_identifier')
    expect(result[:orders].first[:order_number]).to eq('30564')
  end

  it 'looks up orders by a customer-provided email address' do
    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::LIST_ORDERS, hash_including(customerEmail: { eq: 'buyer@example.com' }))
      .and_return(order_response(order_payload(id: 'order-1', order_number: '30564')))

    result = described_class.new(account: account, conversation: conversation, identifiers: { email: ' Buyer@Example.com ' }).call

    expect(result).to include(status: 'ok', result_type: 'show_order_status', matched_by: 'email')
    expect(result[:orders].first[:order_number]).to eq('30564')
  end

  it 'asks for clarification when contact email matches multiple orders' do
    contact.update!(email: 'buyer@example.com')
    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::LIST_ORDERS, hash_including(customerEmail: { eq: 'buyer@example.com' }))
      .and_return(
        order_response(
          order_payload(id: 'order-1', order_number: '30564', ordered_at: 1_700_000_000_000),
          order_payload(id: 'order-2', order_number: '30565', ordered_at: 1_700_100_000_000)
        )
      )

    result = described_class.new(account: account, conversation: conversation).call

    expect(result).to include(status: 'ok', result_type: 'clarify_order', matched_by: 'contact_email', total_matches: 2)
    expect(result[:orders].map { |order| order[:order_number] }).to eq(%w[30565 30564])
    expect(result[:orders].first).not_to include(:packages, :total, :items)
  end

  it 'uses a customer-provided phone number as an internal customer resolver' do
    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::RESOLVE_CUSTOMERS, hash_including(phone: { eq: '+905419719978' }))
      .and_return('listCustomer' => { 'data' => [{ 'id' => 'customer-1' }] })
    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::LIST_ORDERS, hash_including(customerId: { eq: 'customer-1' }))
      .and_return(order_response(order_payload(id: 'order-1', order_number: '30564')))

    result = described_class.new(account: account, conversation: conversation, identifiers: { phone: '00 90 541 971 99 78' }).call

    expect(result).to include(status: 'ok', result_type: 'show_order_status', matched_by: 'phone')
    expect(result[:orders].first[:order_number]).to eq('30564')
  end

  it 'uses phone only as an internal customer resolver before searching orders' do
    contact.update!(phone_number: '+905419719978')

    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::RESOLVE_CUSTOMERS, hash_including(phone: { eq: '+905419719978' }))
      .and_return('listCustomer' => { 'data' => [{ 'id' => 'customer-1' }] })

    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::LIST_ORDERS, hash_including(customerId: { eq: 'customer-1' }))
      .and_return(order_response(order_payload(id: 'order-1', order_number: '30564')))

    result = described_class.new(account: account, conversation: conversation).call

    expect(result).to include(status: 'ok', result_type: 'show_order_status', matched_by: 'contact_phone')
    expect(result[:orders].first[:order_number]).to eq('30564')
  end

  it 'returns a warning instead of inventing tracking details when Ikas omits tracking info' do
    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::LIST_ORDERS, hash_including(orderNumber: { eq: '30564' }))
      .and_return(order_response(order_payload(id: 'order-1', order_number: '30564', tracking: false)))

    result = described_class.new(account: account, conversation: conversation, identifiers: { order_identifier: '30564' }).call

    expect(result).to include(status: 'ok', result_type: 'show_order_status')
    expect(result[:warnings]).to include('tracking_info_missing')
    expect(result[:orders].first[:packages].first[:tracking]).to eq({})
  end

  it 'does not fall back to contact identifiers when a provided order number is not found' do
    contact.update!(email: 'buyer@example.com')
    expect(client).to receive(:execute)
      .with(Integrations::Ikas::OrderLookupQueries::LIST_ORDERS, hash_including(orderNumber: { eq: 'missing' }))
      .and_return(order_response)

    result = described_class.new(account: account, conversation: conversation, identifiers: { order_identifier: 'missing' }).call

    expect(result).to include(status: 'ok', result_type: 'no_match')
  end

  it 'asks for an identifier when neither args nor contact include one' do
    expect(client).not_to receive(:execute)

    result = described_class.new(account: account, conversation: conversation).call

    expect(result).to include(status: 'ok', result_type: 'needs_identifier')
  end

  it 'returns an integration error when ikas is not enabled' do
    account.disable_features('ikas_integration')
    account.save!

    result = described_class.new(account: account, conversation: conversation, identifiers: { order_identifier: '30564' }).call

    expect(result).to include(status: 'error', error_code: 'ikas_feature_disabled')
  end
end
