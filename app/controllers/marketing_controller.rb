class MarketingController < PublicController
  CANONICAL_URL = 'https://www.kozmopath.com/'.freeze
  DESIGN_CONTRACT_SHA = 'c0c36335a540890f398243534c64b1ca0c9202a2322c1dab28e83f2879904e58'.freeze

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
