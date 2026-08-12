require 'rails_helper'

# Rack::Attack is disabled outside production (see config/initializers/rack_attack.rb),
# so the middleware is exercised directly against the registered throttle rule.
RSpec.describe 'Rack::Attack accounts/ip throttle', type: :request do
  subject(:throttle) { Rack::Attack.throttles['accounts/ip'] }

  around do |example|
    original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    example.run
  ensure
    Rack::Attack.cache.store = original_store
  end

  def signup_request(path, ip, method: 'POST')
    env = Rack::MockRequest.env_for(path, method: method).merge('REMOTE_ADDR' => ip)
    Rack::Attack::Request.new(env)
  end

  it 'limits both public signup endpoints to 5 requests per IP per 30 minutes', :aggregate_failures do
    expect(throttle.limit).to eq(5)
    expect(throttle.period).to eq(30.minutes.to_i)

    5.times do
      expect(throttle.matched_by?(signup_request('/api/v1/accounts', '203.0.113.10'))).to be(false)
    end

    expect(throttle.matched_by?(signup_request('/api/v2/accounts', '203.0.113.10'))).to be(true)
  end

  it 'shares one counter across v1 and v2 signup requests from the same IP' do
    3.times { throttle.matched_by?(signup_request('/api/v1/accounts', '198.51.100.10')) }
    2.times { throttle.matched_by?(signup_request('/api/v2/accounts', '198.51.100.10')) }

    expect(throttle.matched_by?(signup_request('/api/v1/accounts', '198.51.100.10'))).to be(true)
  end

  it 'does not throttle signup requests from a separate IP' do
    5.times { throttle.matched_by?(signup_request('/api/v1/accounts', '203.0.113.10')) }

    expect(throttle.matched_by?(signup_request('/api/v1/accounts', '198.51.100.20'))).to be(false)
  end

  it 'ignores non-POST requests and account sub-resource paths' do
    expect(throttle.matched_by?(signup_request('/api/v1/accounts', '203.0.113.10', method: 'GET'))).to be(false)
    expect(throttle.matched_by?(signup_request('/api/v1/accounts/1', '203.0.113.10'))).to be(false)
    expect(throttle.matched_by?(signup_request('/api/v2/accounts/1', '203.0.113.10'))).to be(false)
  end
end
