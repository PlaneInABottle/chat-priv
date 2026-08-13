class MarketingController < PublicController
  CANONICAL_URL = 'https://www.kozmopath.com/'.freeze
  DESIGN_CONTRACT_SHA = 'a6a69e13212555bdac40df58dfe58a9f439edb71b068e98ac69e1c210cb4a47f'.freeze
  LEGAL_PAGE_URLS = {
    privacy_policy: 'https://www.kozmopath.com/privacy-policy',
    terms_of_service: 'https://www.kozmopath.com/terms-of-service'
  }.freeze
  LEGAL_META_SCOPES = {
    privacy_policy: 'privacy',
    terms_of_service: 'terms'
  }.freeze

  layout 'marketing'
  around_action :use_turkish_locale

  def home
    @structured_data = {
      '@context': 'https://schema.org',
      '@type': 'WebSite',
      name: 'Kozmopath',
      url: CANONICAL_URL,
      inLanguage: 'tr-TR'
    }
  end

  def sitemap
    render formats: [:xml]
  end

  def privacy_policy
    set_legal_meta(:privacy_policy)
  end

  def terms_of_service
    set_legal_meta(:terms_of_service)
  end

  private

  # rubocop:disable Naming/AccessorMethodName
  def set_legal_meta(page_key)
    @canonical_url = LEGAL_PAGE_URLS.fetch(page_key)
    locale_scope = LEGAL_META_SCOPES.fetch(page_key)
    @meta_title = I18n.t("marketing.legal.#{locale_scope}.meta.title")
    @meta_description = I18n.t("marketing.legal.#{locale_scope}.meta.description")
    @structured_data = {
      '@context': 'https://schema.org',
      '@type': 'WebPage',
      name: @meta_title,
      url: @canonical_url,
      inLanguage: 'tr-TR',
      isPartOf: { '@type': 'WebSite', name: 'Kozmopath', url: CANONICAL_URL }
    }
    @support_email = public_support_email
  end
  # rubocop:enable Naming/AccessorMethodName

  def use_turkish_locale(&)
    I18n.with_locale(:tr, &)
  end
end
