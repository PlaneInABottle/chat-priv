# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/ikas_catalog_mvp'

RSpec.describe IkasCatalogMvp::CatalogClient do
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
