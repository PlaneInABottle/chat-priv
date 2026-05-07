require 'rails_helper'

RSpec.describe Integrations::Ikas::ConnectionValidator do
  subject(:result) { described_class.new(**params).perform }

  let(:params) do
    {
      client_id: 'client-id-1234',
      client_secret: 'client-secret-1234',
      store_url: 'https://Test-Store.myikas.com/'
    }
  end

  describe '#perform' do
    it 'normalizes the store host and returns a successful result' do
      stub_request(:post, 'https://test-store.myikas.com/api/admin/oauth/token')
        .with(body: hash_including('grant_type' => 'client_credentials', 'client_id' => 'client-id-1234', 'client_secret' => 'client-secret-1234'))
        .to_return(status: 200, body: { access_token: 'access-token' }.to_json)

      stub_request(:post, 'https://api.myikas.com/api/v1/admin/graphql')
        .to_return(status: 200, body: { data: { me: { id: 'merchant-id' } } }.to_json)

      expect(result.success?).to be true
      expect(result.store_host).to eq('test-store.myikas.com')
      expect(result.client_secret).to eq('client-secret-1234')
    end

    it 'rejects invalid store urls before network requests' do
      params[:store_url] = 'https://example.com'

      expect(result.success?).to be false
      expect(result.error_code).to eq('invalid_store_url')
    end

    it 'uses the existing secret when the update secret is blank' do
      params[:client_secret] = ''
      params[:existing_secret] = 'persisted-secret'

      stub_request(:post, 'https://test-store.myikas.com/api/admin/oauth/token')
        .with(body: hash_including('client_secret' => 'persisted-secret'))
        .to_return(status: 200, body: { access_token: 'access-token' }.to_json)

      stub_request(:post, 'https://api.myikas.com/api/v1/admin/graphql')
        .to_return(status: 200, body: { data: { me: { id: 'merchant-id' } } }.to_json)

      expect(result.success?).to be true
      expect(result.client_secret).to eq('persisted-secret')
    end

    it 'maps auth failures to auth_failed' do
      stub_request(:post, 'https://test-store.myikas.com/api/admin/oauth/token')
        .to_return(status: 401, body: { error: 'invalid_client' }.to_json)

      expect(result.success?).to be false
      expect(result.error_code).to eq('auth_failed')
    end

    it 'maps rate limiting to rate_limited' do
      stub_request(:post, 'https://test-store.myikas.com/api/admin/oauth/token')
        .to_return(status: 429, body: '{}')

      expect(result.success?).to be false
      expect(result.error_code).to eq('rate_limited')
    end

    it 'maps graphql probe failures to probe_failed' do
      stub_request(:post, 'https://test-store.myikas.com/api/admin/oauth/token')
        .to_return(status: 200, body: { access_token: 'access-token' }.to_json)

      stub_request(:post, 'https://api.myikas.com/api/v1/admin/graphql')
        .to_return(status: 200, body: { errors: [{ message: 'boom' }] }.to_json)

      expect(result.success?).to be false
      expect(result.error_code).to eq('probe_failed')
    end

    it 'maps token transport failures to network_error' do
      stub_request(:post, 'https://test-store.myikas.com/api/admin/oauth/token')
        .to_raise(SocketError.new('Failed to connect'))

      expect(result.success?).to be false
      expect(result.error_code).to eq('network_error')
    end

    it 'maps graphql transport failures to network_error' do
      stub_request(:post, 'https://test-store.myikas.com/api/admin/oauth/token')
        .to_return(status: 200, body: { access_token: 'access-token' }.to_json)

      stub_request(:post, 'https://api.myikas.com/api/v1/admin/graphql')
        .to_raise(SocketError.new('Failed to connect'))

      expect(result.success?).to be false
      expect(result.error_code).to eq('network_error')
    end
  end
end
