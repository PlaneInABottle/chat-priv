# frozen_string_literal: true

class AiAgents::WebsiteCrawler
  Result = Data.define(:pages, :source_urls, :knowledge_content)

  MAX_PAGES = 10
  MAX_PAGE_BYTES = 3.megabytes
  MAX_PAGE_CHARACTERS = 10_000
  MAX_TOTAL_CHARACTERS = 80_000
  LINK_CATEGORIES = {
    company: %w[about hakkimizda company kurumsal],
    catalog: %w[products urun urunler categories category katalog catalog collections collection],
    services: %w[services hizmet hizmetler solutions cozum cozumler],
    help: %w[faq sss support destek],
    delivery: %w[shipping kargo delivery teslimat],
    returns: %w[return returns exchange iade degisim],
    policies: %w[policy policies politika warranty garanti payment odeme],
    contact: %w[contact iletisim]
  }.freeze
  LINK_KEYWORDS = LINK_CATEGORIES.values.flatten.freeze
  IGNORED_EXTENSIONS = %w[.jpg .jpeg .png .gif .svg .webp .pdf .zip .mp4 .mp3].freeze

  class InvalidWebsite < StandardError; end

  def self.normalize_url(value)
    candidate = value.to_s.strip
    candidate = "https://#{candidate}" unless candidate.match?(%r{\Ahttps?://}i)
    uri = URI.parse(candidate)
    validate_uri!(uri)

    uri.fragment = nil
    uri.path = '/' if uri.path.blank?
    uri.to_s
  rescue URI::InvalidURIError
    raise InvalidWebsite, 'Website URL is invalid.'
  end

  def self.validate_uri!(uri)
    raise InvalidWebsite, 'Website must use HTTP or HTTPS.' unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    raise InvalidWebsite, 'Website must include a host.' if uri.host.blank?
    raise InvalidWebsite, 'Website must not include credentials.' if uri.userinfo.present?
  end

  def initialize(website_url)
    @website_url = self.class.normalize_url(website_url)
  end

  def perform
    homepage = fetch_page(website_url)
    pages = [homepage]
    candidate_urls(homepage[:document]).first(MAX_PAGES - 1).each do |url|
      pages << fetch_page(url)
    rescue SafeFetch::Error
      next
    end

    extracted_pages = cap_total_content(pages.map { |page| page.except(:document) })
    Result.new(
      pages: extracted_pages,
      source_urls: extracted_pages.pluck(:url),
      knowledge_content: compile_knowledge_content(extracted_pages)
    )
  end

  private

  attr_reader :website_url

  def fetch_page(url)
    html = nil
    SafeFetch.fetch(
      url,
      max_bytes: MAX_PAGE_BYTES,
      open_timeout: 2,
      read_timeout: 10,
      headers: { 'User-Agent' => 'Kozmopath-AI-Onboarding/1.0' },
      allowed_content_type_prefixes: [],
      allowed_content_types: ['text/html']
    ) { |result| html = result.tempfile.read }

    document = Nokogiri::HTML(html)
    {
      url: url,
      title: page_title(document),
      text: extract_text(document.dup),
      document: document
    }
  end

  def candidate_urls(document)
    urls = document.css('a[href]').filter_map do |link|
      normalized_link(link['href'])
    end
    ranked = urls.uniq.sort_by { |url| [-link_score(url), url] }.select { |url| link_score(url).positive? }
    diverse = []
    remaining = []
    seen_categories = Set.new
    ranked.each do |url|
      category = link_category(url)
      target = category && seen_categories.add?(category) ? diverse : remaining
      target << url
    end
    diverse + remaining
  end

  def normalized_link(href)
    return if href.blank? || href.start_with?('#', 'mailto:', 'tel:', 'javascript:')

    uri = URI.join(website_url, href)
    return unless crawlable_uri?(uri)

    uri.fragment = nil
    uri.query = nil
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def crawlable_uri?(uri)
    http_uri = uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    same_host = normalized_host(uri.host) == normalized_host(URI.parse(website_url).host)
    supported_extension = IGNORED_EXTENSIONS.exclude?(File.extname(uri.path).downcase)
    http_uri && same_host && supported_extension
  end

  def normalized_host(host)
    host.to_s.downcase.delete_prefix('www.')
  end

  def link_score(url)
    value = url.downcase
    LINK_KEYWORDS.count { |keyword| value.include?(keyword) }
  end

  def link_category(url)
    value = url.downcase
    LINK_CATEGORIES.find { |_category, keywords| keywords.any? { |keyword| value.include?(keyword) } }&.first
  end

  def page_title(document)
    document.at_css('meta[property="og:title"]')&.[]('content').presence || document.at_css('title')&.text.to_s.strip
  end

  def extract_text(document)
    document.css('script, style, noscript, nav, footer, form, svg').remove
    root = document.at_css('main') || document.at_css('article') || document.at_css('body')
    return '' unless root

    lines = root.css('h1, h2, h3, p, li').filter_map do |node|
      node.text.gsub(/\s+/, ' ').strip.presence
    end
    lines = [root.text.gsub(/\s+/, ' ').strip] if lines.empty?
    lines.uniq.join("\n").truncate(MAX_PAGE_CHARACTERS, omission: '')
  end

  def cap_total_content(pages)
    remaining = MAX_TOTAL_CHARACTERS
    pages.each_with_object([]) do |page, result|
      next if remaining <= 0

      text = page[:text].to_s.first(remaining)
      remaining -= text.length
      result << page.merge(text: text) if text.present?
    end
  end

  def compile_knowledge_content(pages)
    pages.filter_map do |page|
      text = page[:text].to_s.strip
      next if text.blank?

      title = page[:title].to_s.strip.presence || page[:url]
      "# #{title}\nSource: #{page[:url]}\n#{text}"
    end.join("\n\n").first(AiKnowledgeSource::MAX_CONTENT_LENGTH)
  end
end
