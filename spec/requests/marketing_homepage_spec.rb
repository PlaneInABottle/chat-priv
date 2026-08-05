require 'rails_helper'

RSpec.describe 'Kozmopath marketing homepage', type: :request do
  marketing_hosts = %w[kozmopath.com www.kozmopath.com]
  section_ids = %w[
    hero
    from-question-to-product
    how-it-works
    catalog-product-presentation
    web-and-whatsapp
    human-handoff
    control-and-boundaries
    final-cta
    footer
  ]
  login_url = 'https://app.kozmopath.com/app/login'
  contract_html_sha = 'ffaf9119d2490eb64e4f3c4691ca84195c79170f06ffeb7cc44750430700e5fc'

  def document
    Nokogiri::HTML5(response.body)
  end

  shared_examples 'the approved marketing surface' do |marketing_host|
    before do
      host! marketing_host
      get '/'
    end

    it 'renders the approved Turkish content and section order without client-side rendering' do
      expect(response).to have_http_status(:ok)
      expect(document.at_css('html')['lang']).to eq('tr')
      expect(document.at_css('meta[name="kozmopath-design-contract"]')['content']).to eq(contract_html_sha)
      expect(document.at_css('h1').text.squish).to eq('Mağazanı bilen yapay zekâ, müşterine doğru cevabı verir.')
      expect(document.css('[data-page-section]').map { |section| section['id'] }).to eq(section_ids)
      expect(document.css('script:not([type="application/ld+json"])')).to be_empty
    end

    it 'preserves the controlled product proof and its disclosure' do
      expect(document.text).to include('Siyah Bisiklet Yaka Sweatshirt')
      expect(document.text).to include('Kontrollü demo verisi · gerçek müşteri kaydı değildir')
    end

    it 'keeps the real login destination and exposes no dead demo destination' do
      login_links = document.css("a[href='#{login_url}']")
      demo_status = document.at_css('.demo-availability')

      expect(login_links.length).to be >= 3
      expect(demo_status.name).to eq('span')
      expect(demo_status['aria-disabled']).to eq('true')
      expect(demo_status['href']).to be_nil
      expect(demo_status['tabindex']).to be_nil
      expect(document.css('a[href*="calendly"], a[href*="/demo"]')).to be_empty
    end

    it 'provides mobile navigation and valid in-page anchor targets without JavaScript' do
      mobile_menu = document.at_css('details.mobile-menu')
      mobile_links = mobile_menu.css('nav a[href^="#"]')
      target_ids = document.css('[id]').to_h { |node| [node['id'], true] }

      expect(mobile_menu.at_css('summary')['aria-label']).to eq('Menüyü aç')
      expect(mobile_links.map { |link| link['href'] }).to eq(%w[#how-it-works #catalog-product-presentation #human-handoff])
      mobile_links.each { |link| expect(target_ids).to include(link['href'].delete_prefix('#')) }
    end

    it 'uses semantic landmarks, accessible images, and a logical heading outline' do
      expect(document.css('header, main, footer').map(&:name)).to eq(%w[header main footer])
      expect(document.css('h1').length).to eq(1)
      expect(document.css('h2').length).to eq(7)
      expect(document.css('img').all? { |image| image.key?('alt') }).to be(true)
      expect(document.css('[tabindex]').none? { |node| node['tabindex'].to_i.positive? }).to be(true)
      expect(document.at_css('a.skip-link')['href']).to eq('#main')
    end

    it 'publishes canonical, social, robots, and structured metadata for the www origin' do
      canonical = 'https://www.kozmopath.com/'
      schema = JSON.parse(document.at_css('script[type="application/ld+json"]').text)

      expect(document.at_css('title').text).to eq('Kozmopath — İkas mağazanı bilen müşteri iletişimi')
      expect(document.at_css('meta[name="description"]')['content']).to include('ikas ürün kataloğunu')
      expect(document.at_css('meta[name="robots"]')['content']).to eq('index,follow,max-image-preview:large')
      expect(document.at_css('link[rel="canonical"]')['href']).to eq(canonical)
      expect(document.at_css('meta[property="og:url"]')['content']).to eq(canonical)
      expect(schema.fetch('@type')).to eq('WebSite')
      expect(schema.fetch('url')).to eq(canonical)
    end
  end

  marketing_hosts.each do |marketing_host|
    it_behaves_like 'the approved marketing surface', marketing_host
  end

  describe 'GET /sitemap.xml' do
    it 'returns only the canonical public marketing URL' do
      host! 'www.kozmopath.com'
      get '/sitemap.xml'

      sitemap = Nokogiri::XML(response.body)

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/xml')
      expect(sitemap.xpath('//xmlns:url/xmlns:loc').map(&:text)).to eq(['https://www.kozmopath.com/'])
    end
  end
end
