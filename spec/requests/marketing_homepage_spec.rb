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
  signup_url = 'https://app.kozmopath.com/app/auth/signup'
  login_url = 'https://app.kozmopath.com/app/login'

  def document
    Nokogiri::HTML5(response.body)
  end

  shared_examples 'the approved marketing surface' do |marketing_host|
    before do
      allow(GlobalConfigService).to receive(:account_signup_enabled?).and_return(true)
      host! marketing_host
      get '/'
    end

    it 'renders the approved Turkish content and section order without client-side rendering' do
      expect(response).to have_http_status(:ok)
      expect(document.at_css('html')['lang']).to eq('tr')
      expect(document.at_css('meta[name="kozmopath-design-contract"]')['content']).to eq(MarketingController::DESIGN_CONTRACT_SHA)
      expect(document.at_css('h1').text.squish).to eq('Mağazanı bilen yapay zekâ, müşterine doğru cevabı verir.')
      expect(document.css('[data-page-section]').map { |section| section['id'] }).to eq(section_ids)
      expect(document.css('script:not([type="application/ld+json"])')).to be_empty
      expect(response.body).not_to include('Translation missing')
    end

    it 'keeps the design contract fingerprint stable against the meta-neutralized body' do
      neutralized_body = response.body.gsub(/(<meta name="kozmopath-design-contract" content=")[0-9a-f]{64}(">)/, '\1\2')

      expect(neutralized_body).to include('kozmopath-design-contract" content="">')
      expect(neutralized_body).not_to match(/content="[0-9a-f]{64}"/)
      expect(Digest::SHA256.hexdigest(neutralized_body)).to eq(MarketingController::DESIGN_CONTRACT_SHA)
      expect(document.at_css('meta[name="kozmopath-design-contract"]')['content']).to eq(MarketingController::DESIGN_CONTRACT_SHA)
    end

    it 'preserves the controlled product proof and its disclosure' do
      expect(document.text).to include('Siyah Bisiklet Yaka Sweatshirt')
      expect(document.text).to include('Kontrollü demo verisi · gerçek müşteri kaydı değildir')
    end

    it 'uses the authoritative wordmarks and no-badge router thumbnail' do
      expect(document.at_css('header .brand-logo')['src']).to eq('/brand-assets/logo.svg')
      expect(document.at_css('.router-brand-symbol')['src']).to eq('/brand-assets/logo_thumbnail.svg')
      expect(document.at_css('footer .brand-logo')['src']).to eq('/brand-assets/logo_dark.svg')
      expect(document.css('[src*="logo_thumbnail_badge"], .brand-mark, .mini-mark')).to be_empty
    end

    it 'renders the approved catalog anatomy, answer router, handoff dossier, and control console grammars' do
      anatomy = document.at_css('[data-evidence-grammar="catalog-anatomy-sheet"]')
      router = document.at_css('[data-signature-component="catalog-answer-router"]')
      dossier = document.at_css('[data-evidence-grammar="context-handoff-dossier"]')

      expect(anatomy.css('.anatomy-media, .anatomy-fields, .presentation-modes, .anatomy-disclosure').length).to eq(4)
      expect(router.css('[data-route-node]').map { |node| node['data-route-node'] }).to eq(%w[source router rich inbox text])
      expect(dossier.css('[data-context]').map { |node| node['data-context'] }).to include(
        'conversation', 'reason', 'ownership', 'queue', 'status', 'continuity'
      )
      expect(document.at_css('.control-console')).to be_present
      expect(document.css('.control-flow li').length).to eq(4)
    end

    it 'keeps rich catalog promises bounded to Web and WhatsApp' do
      rich_output = document.at_css('[data-route-node="rich"]')
      instagram = document.at_css('[data-route-node="inbox"][data-channel="instagram"]')
      api = document.at_css('[data-route-node="text"][data-channel="api"]')

      expect(rich_output.css('[data-channel]').map { |node| node['data-channel'] }).to eq(%w[web-widget whatsapp])
      expect(instagram.text).to include('burada zengin katalog kartı sözü yok')
      expect(api.text).to include('Doğal metin; görsel ürün kartı gibi gösterilmez')
      expect(document.at_css('.channel-boundary').text).to include('Zengin katalog sunumu Web sitesi ve WhatsApp ile sınırlıdır')
    end

    it 'renders the selected freemium hierarchy with exact production destinations' do
      login_links = document.css("a[href='#{login_url}']")
      freemium_links = document.css("a[data-freemium-cta][href='#{signup_url}']")

      expect(login_links.length).to be >= 3
      expect(freemium_links.map { |link| link['data-freemium-cta'] }).to eq(%w[header mobile-menu hero-primary final])
      expect(freemium_links.map { |link| link.text.squish }).to eq([
                                                                     'Ücretsiz başla',
                                                                     'Ücretsiz başla',
                                                                     'Ücretsiz başla',
                                                                     'Ücretsiz hesabını oluştur'
                                                                   ])
      expect(document.at_css('.announcement').text.squish).to eq('✦ Her ay 100 yapay zekâ sohbeti.')
      expect(document.at_css('.hero-freemium-truth').text.squish).to include('Ayda 600 yapay zekâ çalışma alanı kredisi.')
      expect(document.at_css('.final-cta').text.squish).to include('Süresiz ücretsiz.')
      expect(document.css('a[href*="calendly"], a[href*="/demo"]')).to be_empty
    end

    it 'makes no trial, card, or automatic-billing claims on the signup-enabled homepage' do
      expect(response.body).not_to match(/(kredi kartı|otomatik ücretlendirme|14 gün|deneme süren)/i)
      expect(document.text).not_to include('No credit card')
      expect(document.css('[data-trial-cta], .trial-announcement, .hero-trial-truth, .final-trial-button')).to be_empty
    end

    it 'provides mobile navigation and valid in-page anchor targets without JavaScript' do
      mobile_menu = document.at_css('details.mobile-menu')
      mobile_links = mobile_menu.css('nav a[href^="#"]')
      target_ids = document.css('[id]').to_h { |node| [node['id'], true] }

      expect(mobile_menu.at_css('summary')['aria-label']).to eq('Menüyü aç')
      expect(mobile_links.map { |link| link['href'] }).to eq(%w[#how-it-works #catalog-product-presentation #human-handoff])
      mobile_links.each { |link| expect(target_ids).to include(link['href'].delete_prefix('#')) }
      expect(mobile_menu.at_css('summary').css('span').length).to eq(3)
      expect(mobile_menu.at_css("a[data-freemium-cta='mobile-menu']")['href']).to eq(signup_url)
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

    it "keeps the existing non-freemium fallback when signup is disabled on #{marketing_host}" do
      allow(GlobalConfigService).to receive(:account_signup_enabled?).and_return(false)
      host! marketing_host

      get '/'

      expect(response).to have_http_status(:ok)
      expect(document.css("a[href='#{signup_url}'], [data-freemium-cta]")).to be_empty
      expect(document.at_css('.announcement').text.squish).to eq('✦ İkas mağazaları için katalog bağlamlı yapay zekâ desteği')
      demo_status = document.at_css('.demo-availability')
      expect(demo_status.name).to eq('span')
      expect(demo_status['aria-disabled']).to eq('true')
      expect(demo_status['href']).to be_nil
    end
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
