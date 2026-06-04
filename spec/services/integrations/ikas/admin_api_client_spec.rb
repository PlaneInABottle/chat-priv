require 'rails_helper'

RSpec.describe Integrations::Ikas::AdminApiClient do
  subject(:client) do
    described_class.new(
      store_host: 'https://Test-Store.myikas.com/',
      client_id: 'client-id-1234',
      client_secret: 'client-secret-1234',
      graphql_url: 'https://api.myikas.test/graphql'
    )
  end

  describe '#execute' do
    it 'fetches an access token and executes GraphQL with bearer auth' do
      stub_request(:post, 'https://test-store.myikas.com/api/admin/oauth/token')
        .with(body: hash_including('client_id' => 'client-id-1234', 'client_secret' => 'client-secret-1234'))
        .to_return(status: 200, body: { access_token: 'access-token' }.to_json)

      stub_request(:post, 'https://api.myikas.test/graphql')
        .with(headers: { 'Authorization' => 'Bearer access-token' })
        .to_return(status: 200, body: { data: { me: { id: 'merchant-id' } } }.to_json)

      expect(client.execute('{ me { id } }')).to eq('me' => { 'id' => 'merchant-id' })
    end

    it 'raises a sanitized error when GraphQL returns errors' do
      stub_request(:post, 'https://test-store.myikas.com/api/admin/oauth/token')
        .to_return(status: 200, body: { access_token: 'access-token' }.to_json)

      stub_request(:post, 'https://api.myikas.test/graphql')
        .to_return(status: 200, body: { errors: [{ message: 'bad query' }] }.to_json)

      expect { client.execute('{ bad }') }.to raise_error(described_class::Error, /Ikas GraphQL errors/)
    end

    it 'rejects invalid store hosts before fetching a token' do
      invalid_client = described_class.new(store_host: 'example.com', client_id: 'id', client_secret: 'secret')

      expect { invalid_client.execute('{ me { id } }') }.to raise_error(described_class::Error, /store host is invalid/)
    end
  end
end
