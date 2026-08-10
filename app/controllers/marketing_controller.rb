class MarketingController < PublicController
  CANONICAL_URL = 'https://www.kozmopath.com/'.freeze
  DESIGN_CONTRACT_SHA = 'a8ab04da44e22152c99c533569c80f4f8d3d44f1ee4a55dea61eefb86fffb95b'.freeze

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
