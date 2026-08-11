require 'rails_helper'

RSpec.describe 'Kozmopath marketing legal pages', type: :request do
  marketing_hosts = %w[kozmopath.com www.kozmopath.com marketing.localhost]
  pages = {
    '/privacy-policy' => { key: :privacy_policy, prefix: 'privacy', anchors: %w[KVKK] },
    '/terms-of-service' => { key: :terms_of_service, prefix: 'terms', anchors: %w[Türkiye KVKK] }
  }

  def document
    Nokogiri::HTML5(response.body)
  end

  shared_examples 'a legal page on the marketing surface' do |path, page_config|
    let(:page_scope) { "marketing.legal.#{page_config[:prefix]}" }

    before do
      allow(GlobalConfigService).to receive(:load)
        .with('MAILER_SUPPORT_EMAIL', 'support@kozmopath.com')
        .and_return('support@kozmopath.com')
      host! marketing_host
      get path
    end

    it 'renders the Turkish page with its own metadata' do
      expect(response).to have_http_status(:ok)
      expect(document.at_css('html')['lang']).to eq('tr')
      meta_title = I18n.t("#{page_scope}.meta.title", locale: :tr)
      meta_description = I18n.t("#{page_scope}.meta.description", locale: :tr)

      expect(document.at_css('title').text).to eq(meta_title)
      expect(document.at_css('meta[name="description"]')['content']).to eq(meta_description)
      expect(document.at_css('meta[name="robots"]')['content']).to eq('index,follow,max-image-preview:large')
      expect(document.at_css('meta[name="kozmopath-design-contract"]')['content']).to eq(MarketingController::DESIGN_CONTRACT_SHA)
    end

    it 'points canonical and Open Graph metadata at the page URL' do
      meta_title = I18n.t("#{page_scope}.meta.title", locale: :tr)
      meta_description = I18n.t("#{page_scope}.meta.description", locale: :tr)
      canonical = MarketingController::LEGAL_PAGE_URLS.fetch(page_config[:key])

      expect(document.at_css('link[rel="canonical"]')['href']).to eq(canonical)
      expect(document.at_css('meta[property="og:url"]')['content']).to eq(canonical)
      expect(document.at_css('meta[property="og:title"]')['content']).to eq(meta_title)
      expect(document.at_css('meta[property="og:description"]')['content']).to eq(meta_description)
    end

    it 'emits WebPage JSON-LD linked to the WebSite' do
      schema = JSON.parse(document.at_css('script[type="application/ld+json"]').text)
      canonical = MarketingController::LEGAL_PAGE_URLS.fetch(page_config[:key])

      expect(schema.fetch('@type')).to eq('WebPage')
      expect(schema.fetch('url')).to eq(canonical)
      expect(schema.fetch('inLanguage')).to eq('tr-TR')
      expect(schema.fetch('isPartOf')).to eq(
        { '@type' => 'WebSite', 'name' => 'Kozmopath', 'url' => MarketingController::CANONICAL_URL }
      )
    end

    it 'renders every mandated section once plus a single final contact section' do
      section_keys = I18n.t("#{page_scope}.sections", locale: :tr).keys
      expected_ids = section_keys.map { |key| "#{page_config[:prefix]}-#{key}" } + ["#{page_config[:prefix]}-contact"]
      rendered_ids = document.css('.legal-section').map { |section| section['id'] }

      expect(rendered_ids).to eq(expected_ids)
      expect(rendered_ids.uniq.length).to eq(rendered_ids.length)
      expect(document.css('a[href^="mailto:"]').length).to eq(1)
      expect(document.text).to include('support@kozmopath.com')
      expect(document.at_css('.legal-updated').text).to include('12 Ağustos 2026')
    end

    it 'keeps the required content anchors in the Turkish copy' do
      page_config[:anchors].each { |anchor| expect(document.text).to include(anchor) }
    end

    it 'stays server-rendered with a single h1 and a working skip link' do
      expect(document.css('script:not([type="application/ld+json"])')).to be_empty
      expect(document.css('h1').length).to eq(1)
      expect(document.at_css('a.skip-link')['href']).to eq('#main')
    end

    it 'renders the brand header, legal footer links and no missing translations' do
      expect(document.at_css('header .brand')['href']).to eq('/')
      expect(document.at_css('header .brand img')['src']).to eq('/brand-assets/logo.svg')
      expect(document.css('footer.site-footer a[href="/privacy-policy"]')).to be_present
      expect(document.css('footer.site-footer a[href="/terms-of-service"]')).to be_present
      expect(response.body).not_to include('Translation missing')
    end
  end

  marketing_hosts.each do |host|
    context 'when served on the marketing host' do
      let(:marketing_host) { host }

      pages.each do |path, page_config|
        context path do
          it_behaves_like 'a legal page on the marketing surface', path, page_config
        end
      end
    end
  end

  it 'returns 404 for both legal pages on the app host' do
    host! 'app.kozmopath.com'

    get '/privacy-policy'
    expect(response).to have_http_status(:not_found)

    get '/terms-of-service'
    expect(response).to have_http_status(:not_found)
  end
end
