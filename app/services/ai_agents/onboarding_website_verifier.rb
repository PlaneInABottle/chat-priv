# frozen_string_literal: true

require 'ipaddr'
require 'public_suffix'

class AiAgents::OnboardingWebsiteVerifier
  Result = Data.define(:website_url, :hostname, :title, :verification_token)

  TOKEN_LIFETIME = 30.minutes
  TOKEN_PURPOSE = 'ai_agent_onboarding_website'
  RATE_LIMIT = 5
  RATE_LIMIT_WINDOW = 1.minute

  class RateLimited < StandardError
    attr_reader :retry_after

    def initialize(retry_after)
      @retry_after = retry_after
      super('Website verification is temporarily unavailable. Please try again later.')
    end
  end

  def self.verified_url!(account:, website_url:, verification_token:)
    normalized_url = AiAgents::WebsiteCrawler.normalize_url(website_url)
    payload = verifier.verify(verification_token.to_s, purpose: TOKEN_PURPOSE)
    valid_account = payload['account_id'] == account.id
    valid_url = ActiveSupport::SecurityUtils.secure_compare(payload['website_url'], normalized_url)
    return normalized_url if valid_account && valid_url

    raise AiAgents::WebsiteCrawler::InvalidWebsite, 'Website verification does not match this account.'
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    raise AiAgents::WebsiteCrawler::InvalidWebsite, 'Website verification is missing or expired.'
  end

  def initialize(account:, website_url:)
    @account = account
    @website_url = website_url
  end

  def perform
    enforce_rate_limit!
    normalized_url = AiAgents::WebsiteCrawler.normalize_url(website_url)
    hostname = URI.parse(normalized_url).host.downcase
    document = fetch_homepage(normalized_url)

    Result.new(
      website_url: normalized_url,
      hostname: hostname.delete_prefix('www.'),
      title: page_title(document),
      verification_token: self.class.send(:issue_token, account: account, website_url: normalized_url)
    )
  end

  private

  attr_reader :account, :website_url

  def enforce_rate_limit!
    Redis::Alfred.set(rate_limit_key, 0, nx: true, ex: RATE_LIMIT_WINDOW.to_i)
    count = Redis::Alfred.incr(rate_limit_key)
    return if count <= RATE_LIMIT

    retry_after = Redis::Alfred.ttl(rate_limit_key).to_i.clamp(1, RATE_LIMIT_WINDOW.to_i)
    raise RateLimited, retry_after
  end

  def rate_limit_key
    format(Redis::Alfred::AI_AGENT_ONBOARDING_WEBSITE_VERIFICATION, account_id: account.id)
  end

  def self.issue_token(account:, website_url:)
    verifier.generate(
      { 'account_id' => account.id, 'website_url' => website_url },
      expires_in: TOKEN_LIFETIME,
      purpose: TOKEN_PURPOSE
    )
  end

  def self.verifier
    Rails.application.message_verifier(TOKEN_PURPOSE)
  end

  private_class_method :issue_token, :verifier

  def fetch_homepage(url)
    html = nil
    SafeFetch.fetch(
      url,
      max_bytes: AiAgents::WebsiteCrawler::MAX_PAGE_BYTES,
      open_timeout: 2,
      read_timeout: 5,
      headers: { 'User-Agent' => 'Kozmopath-AI-Onboarding/1.0' },
      allowed_content_type_prefixes: [],
      allowed_content_types: ['text/html']
    ) { |result| html = result.tempfile.read }
    Nokogiri::HTML(html)
  end

  def page_title(document)
    title = document.at_css('meta[property="og:site_name"]')&.[]('content').presence ||
            document.at_css('meta[property="og:title"]')&.[]('content').presence ||
            document.at_css('title')&.text.to_s.strip.presence
    title.to_s.gsub(/\s+/, ' ').strip.truncate(120, omission: '')
  end
end
