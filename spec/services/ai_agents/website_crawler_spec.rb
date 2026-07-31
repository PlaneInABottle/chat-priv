require 'rails_helper'

RSpec.describe AiAgents::WebsiteCrawler do
  before do
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with('example.com').and_return(['93.184.216.34'])
  end

  it 'extracts the homepage and diverse relevant same-site pages for instructions and knowledge' do
    homepage = <<~HTML
      <html><head><title>Example Store</title></head><body>
        <nav>Repeated navigation <a href="/about">About us</a><a href="/products">Products</a></nav>
        <main><h1>Comfort for every room</h1><p>We make custom window products.</p></main>
        <a href="/services">Services</a><a href="/faq">FAQ</a>
        <a href="/contact">Contact</a><a href="/blog">Blog</a>
        <a href="https://other.example.org/about">External</a>
      </body></html>
    HTML
    stub_request(:get, 'https://example.com/').to_return(status: 200, body: homepage, headers: { 'Content-Type' => 'text/html' })
    %w[about products services faq contact].each do |path|
      stub_request(:get, "https://example.com/#{path}").to_return(
        status: 200,
        body: "<main><h1>#{path.titleize}</h1><p>Useful #{path} information.</p></main>",
        headers: { 'Content-Type' => 'text/html' }
      )
    end

    result = described_class.new('example.com').perform

    expect(result.pages.length).to eq(6)
    expect(result.source_urls.first).to eq('https://example.com/')
    expect(result.pages.first[:text]).to include('Comfort for every room', 'custom window products')
    expect(result.pages.first[:text]).not_to include('Repeated navigation')
    expect(result.source_urls).not_to include('https://example.com/blog', 'https://other.example.org/about')
    expect(result.knowledge_content).to include('# Example Store', 'Source: https://example.com/')
  end

  it 'rejects non-http website values' do
    expect { described_class.new('javascript:alert(1)') }.to raise_error(described_class::InvalidWebsite)
  end

  it 'rejects private network websites before any request is made' do
    expect { described_class.new('http://127.0.0.1/internal') }
      .to raise_error(described_class::InvalidWebsite, 'Website must use a public domain.')
    expect { described_class.normalize_url('http://192.168.1.10') }
      .to raise_error(described_class::InvalidWebsite, 'Website must use a public domain.')
    expect { described_class.normalize_url('http://localhost:3000') }
      .to raise_error(described_class::InvalidWebsite, 'Website must use a public domain.')
  end

  it 'still leaves SafeFetch as the backstop when private networks are explicitly allowed' do
    with_modified_env SAFE_FETCH_ALLOW_PRIVATE_NETWORK: 'true' do
      expect(described_class.normalize_url('http://localhost:3000')).to eq('http://localhost:3000/')
    end
  end
end
