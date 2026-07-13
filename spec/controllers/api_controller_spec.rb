require 'rails_helper'

RSpec.describe 'API Base', type: :request do
  describe 'request to api base url' do
    it 'returns a technology-neutral status' do
      allow(Redis).to receive(:new).and_return(instance_double(Redis, ping: true))

      get '/api/'

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq('status' => 'ok')
    end

    it 'reports a failing status without exposing the failed service' do
      allow(Redis).to receive(:new).and_raise(Redis::CannotConnectError)

      get '/api/'

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq('status' => 'failing')
    end
  end
end
