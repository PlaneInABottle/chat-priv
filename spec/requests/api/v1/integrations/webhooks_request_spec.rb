require 'rails_helper'

RSpec.describe 'Api::V1::Integrations::Webhooks' do
  let(:signing_secret) { 'slack-signing-secret' }
  let(:timestamp) { Time.current.to_i }
  let(:payload) do
    {
      type: 'url_verification',
      challenge: 'verification-challenge',
      unexpected: 'discard-me'
    }
  end
  let(:body) { payload.to_json }

  before do
    allow(GlobalConfigService).to receive(:load).with('SLACK_SIGNING_SECRET', nil).and_return(signing_secret)
  end

  describe 'POST /api/v1/integrations/webhooks' do
    it 'accepts a valid Slack signature and forwards only supported fields' do
      builder = instance_double(Integrations::Slack::IncomingMessageBuilder, perform: { challenge: payload[:challenge] })
      expect(Integrations::Slack::IncomingMessageBuilder).to receive(:new) do |permitted_params|
        expect(permitted_params.to_h).to include('type' => payload[:type], 'challenge' => payload[:challenge])
        expect(permitted_params.to_h).not_to have_key('unexpected')
        builder
      end

      post '/api/v1/integrations/webhooks', params: body, headers: signed_headers

      expect(response).to have_http_status(:success)
      expect(response.parsed_body).to eq('challenge' => payload[:challenge])
    end

    it 'preserves the fields required to deliver signed link unfurls' do
      link_payload = {
        type: 'event_callback',
        event: {
          type: 'link_shared',
          channel: 'C123',
          user: 'U123',
          unfurl_id: 'unfurl-123',
          source: 'conversations_history',
          links: [{ domain: 'app.example.com', url: 'https://app.example.com/accounts/1/conversations/2' }]
        }
      }
      link_body = link_payload.to_json
      builder = instance_double(Integrations::Slack::IncomingMessageBuilder, perform: nil)
      expect(Integrations::Slack::IncomingMessageBuilder).to receive(:new) do |permitted_params|
        expect(permitted_params.to_h.dig('event', 'unfurl_id')).to eq('unfurl-123')
        expect(permitted_params.to_h.dig('event', 'source')).to eq('conversations_history')
        builder
      end

      post '/api/v1/integrations/webhooks',
           params: link_body,
           headers: signed_headers(timestamp, link_body)

      expect(response).to have_http_status(:success)
    end

    it 'rejects requests without a signature' do
      expect(Integrations::Slack::IncomingMessageBuilder).not_to receive(:new)

      post '/api/v1/integrations/webhooks', params: body, headers: { 'CONTENT_TYPE' => 'application/json' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects an invalid signature' do
      expect(Integrations::Slack::IncomingMessageBuilder).not_to receive(:new)

      post '/api/v1/integrations/webhooks', params: body,
                                            headers: signed_headers.merge('X-Slack-Signature' => 'v0=invalid')

      expect(response).to have_http_status(:unauthorized)
    end

    it 'rejects signatures outside the replay window' do
      stale_timestamp = 6.minutes.ago.to_i
      expect(Integrations::Slack::IncomingMessageBuilder).not_to receive(:new)

      post '/api/v1/integrations/webhooks', params: body, headers: signed_headers(stale_timestamp)

      expect(response).to have_http_status(:unauthorized)
    end

    it 'fails closed when the signing secret is not configured' do
      allow(GlobalConfigService).to receive(:load).with('SLACK_SIGNING_SECRET', nil).and_return(nil)
      expect(Integrations::Slack::IncomingMessageBuilder).not_to receive(:new)

      post '/api/v1/integrations/webhooks', params: body, headers: signed_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  private

  def signed_headers(request_timestamp = timestamp, request_body = body)
    signature_base = "v0:#{request_timestamp}:#{request_body}"
    signature = OpenSSL::HMAC.hexdigest('SHA256', signing_secret, signature_base)

    {
      'CONTENT_TYPE' => 'application/json',
      'X-Slack-Request-Timestamp' => request_timestamp.to_s,
      'X-Slack-Signature' => "v0=#{signature}"
    }
  end
end
