class MarketingController < PublicController
  CANONICAL_URL = 'https://www.kozmopath.com/'.freeze
  DESIGN_CONTRACT_SHA = '9643879c665fc4dffccbfc5e84b74ad57c7bb127b389f63865d2464c83c37d46'.freeze

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
