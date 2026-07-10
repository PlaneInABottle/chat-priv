require 'rails_helper'

RSpec.describe 'AI data retention routing', type: :routing do
  let(:path) { '/api/v1/accounts/1/ai_data_retention' }

  it 'does not expose retention policy or cleanup routes to account users' do
    expect(get: path).not_to be_routable
    expect(patch: path).not_to be_routable
    expect(post: "#{path}/purge").not_to be_routable
  end
end
