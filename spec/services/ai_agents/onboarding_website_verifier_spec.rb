require 'rails_helper'

RSpec.describe AiAgents::OnboardingWebsiteVerifier do
  let(:account) { create(:account) }

  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
    allow(Redis::Alfred).to receive(:incr).and_return(1)
    allow(Redis::Alfred).to receive(:expire)
    allow(Redis::Alfred).to receive(:ttl).and_return(described_class::RATE_LIMIT_WINDOW.to_i)
  end

  it 'verifies a reachable public website and returns its identity' do
    stub_request(:get, 'https://example.com/').to_return(
      status: 200,
      body: '<html><head><meta property="og:site_name" content="  Example Store  "></head></html>',
      headers: { 'Content-Type' => 'text/html' }
    )

    result = described_class.new(account: account, website_url: 'example.com').perform

    expect(result.to_h).to include(
      website_url: 'https://example.com/',
      hostname: 'example.com',
      title: 'Example Store'
    )
    expect(
      described_class.verified_url!(
        account: account,
        website_url: result.website_url,
        verification_token: result.verification_token
      )
    ).to eq('https://example.com/')
  end

  it 'rejects single-label hosts before making a network request' do
    expect do
      described_class.new(account: account, website_url: 'randomvalue').perform
    end.to raise_error(AiAgents::WebsiteCrawler::InvalidWebsite, /public domain/)
  end

  it 'rejects IP address websites before making a network request' do
    expect do
      described_class.new(account: account, website_url: 'https://93.184.216.34').perform
    end.to raise_error(AiAgents::WebsiteCrawler::InvalidWebsite, /public domain/)
  end

  it 'limits website fetches per account' do
    allow(Redis::Alfred).to receive(:incr).and_return(described_class::RATE_LIMIT + 1)
    allow(Redis::Alfred).to receive(:ttl).and_return(23)

    expect do
      described_class.new(account: account, website_url: 'example.com').perform
    end.to raise_error(described_class::RateLimited) { |error| expect(error.retry_after).to eq(23) }

    expect(WebMock).not_to have_requested(:get, 'https://example.com/')
  end

  it 'starts the account rate-limit window on the first verification' do
    stub_request(:get, 'https://example.com/').to_return(
      status: 200,
      body: '<title>Example</title>',
      headers: { 'Content-Type' => 'text/html' }
    )
    expected_key = format(Redis::Alfred::AI_AGENT_ONBOARDING_WEBSITE_VERIFICATION, account_id: account.id)

    described_class.new(account: account, website_url: 'example.com').perform

    expect(Redis::Alfred).to have_received(:expire).with(expected_key, described_class::RATE_LIMIT_WINDOW.to_i)
  end

  it 'does not accept another account or changed URL with the signed verification' do
    stub_request(:get, 'https://example.com/').to_return(
      status: 200,
      body: '<title>Example</title>',
      headers: { 'Content-Type' => 'text/html' }
    )
    result = described_class.new(account: account, website_url: 'example.com').perform

    expect do
      described_class.verified_url!(
        account: create(:account),
        website_url: result.website_url,
        verification_token: result.verification_token
      )
    end.to raise_error(AiAgents::WebsiteCrawler::InvalidWebsite, /does not match/)
    expect do
      described_class.verified_url!(
        account: account,
        website_url: 'example.org',
        verification_token: result.verification_token
      )
    end.to raise_error(AiAgents::WebsiteCrawler::InvalidWebsite, /does not match/)
  end
end
