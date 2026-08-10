class MarketingController < PublicController
  CANONICAL_URL = 'https://www.kozmopath.com/'.freeze
  DESIGN_CONTRACT_SHA = '8d490e9d64145fe3ce6b3cf67fa1ce541b83bb89896aadd1d7c1c7a061157d39'.freeze

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

  private

  def use_turkish_locale(&)
    I18n.with_locale(:tr, &)
  end
end
