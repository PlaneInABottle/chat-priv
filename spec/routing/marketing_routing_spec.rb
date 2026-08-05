require 'rails_helper'

RSpec.describe 'marketing routing', type: :routing do
  it 'routes the apex and www roots to the marketing homepage' do
    expect(get: 'https://kozmopath.com/').to route_to(controller: 'marketing', action: 'home')
    expect(get: 'https://www.kozmopath.com/').to route_to(controller: 'marketing', action: 'home')
  end

  it 'keeps the app root on the existing dashboard surface' do
    expect(get: 'https://app.kozmopath.com/').to route_to(controller: 'dashboard', action: 'index')
  end

  it 'does not expose the marketing sitemap on the app host' do
    expect(get: 'https://app.kozmopath.com/sitemap.xml').not_to be_routable
  end
end
