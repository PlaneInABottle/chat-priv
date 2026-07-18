# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/ikas_catalog_mvp'

RSpec.describe IkasCatalogMvp::CatalogClient do
  it 'loads the merchant identifier used to build canonical image URLs' do
    client = described_class.new(
      client_id: 'client-id',
      client_secret: 'client-secret',
      store_url: 'https://test-store.myikas.com'
    )
    merchant = { 'id' => '05d8a2b7-89af-41b3-b47f-b091868cfd8c' }
    allow(client).to receive(:execute_graphql).with(described_class::GET_MERCHANT_QUERY).and_return('getMerchant' => merchant)

    expect(client.merchants).to eq([merchant])
  end

  it 'rejects a merchant response without an identifier' do
    client = described_class.new(
      client_id: 'client-id',
      client_secret: 'client-secret',
      store_url: 'https://test-store.myikas.com'
    )
    allow(client).to receive(:execute_graphql).with(described_class::GET_MERCHANT_QUERY).and_return('getMerchant' => nil)

    expect { client.merchants }.to raise_error(IkasCatalogMvp::Error, 'Ikas merchant response missing id')
  end

  describe '#send(:access_token)' do
    it 'reports token HTTP failures before parsing the body' do
      response = instance_double(HTTParty::Response, success?: false, code: 401, body: '')
      allow(HTTParty).to receive(:post).and_return(response)

      client = described_class.new(
        client_id: 'client-id',
        client_secret: 'client-secret',
        store_url: 'https://test-store.myikas.com'
      )

      expect { client.send(:access_token) }.to raise_error(IkasCatalogMvp::Error, 'Ikas token HTTP 401')
    end
  end
end
