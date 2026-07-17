# frozen_string_literal: true

require 'uri'

class AiAgents::ToolOutputSanitizer
  URL_FIELD_PATTERN = /(?:\A|_)(?:url|uri|link)s?\z/i
  MARKDOWN_LINK_PATTERN = %r{\[(?<label>[^\]\n]+)\]\((?<url>https?://[^\s)]*)\)}i
  TRAILING_MARKDOWN_LINK_PATTERN = %r{\[(?<label>[^\]\n]+)\]\((?<url>https?://[^\s)]*)\z}i
  BARE_HTTP_URL_PATTERN = %r{https?://[^\s<>\])]+}i

  def initialize(tool_events:, enforce_url_allowlist: false)
    @tool_events = Array(tool_events)
    @enforce_url_allowlist = enforce_url_allowlist
  end

  def sanitize(content)
    answer = content.to_s.strip.presence
    return answer if answer.blank? || (tool_events.empty? && !enforce_url_allowlist)

    answer = repair_truncated_trailing_markdown(answer)
    answer = sanitize_markdown_links(answer)
    sanitize_bare_urls(answer)
  end

  private

  attr_reader :tool_events, :enforce_url_allowlist

  def trusted_urls
    @trusted_urls ||= tool_events.flat_map { |event| urls_in(event['result'] || event[:result]) }.filter_map { |url| normalize_url(url) }.uniq
  end

  def urls_in(value)
    case value
    when Hash
      value.each_with_object([]) do |(key, child), urls|
        urls.concat(Array(child).select { |entry| entry.is_a?(String) }) if key.to_s.match?(URL_FIELD_PATTERN)
        urls.concat(urls_in(child))
      end
    when Array
      value.flat_map { |child| urls_in(child) }
    else
      []
    end
  end

  def repair_truncated_trailing_markdown(answer)
    match = answer.match(TRAILING_MARKDOWN_LINK_PATTERN)
    return answer unless match

    normalized_prefix = normalize_url(match[:url])
    trusted_match = unique_trusted_prefix_match(normalized_prefix)
    return replace_trailing_markdown(answer, match, match[:label]) unless trusted_match

    replacement = "[#{match[:label]}](#{trusted_match})"
    replace_trailing_markdown(answer, match, replacement)
  end

  def unique_trusted_prefix_match(prefix)
    return if prefix.blank?
    return prefix if trusted_urls.include?(prefix)

    matches = trusted_urls.select { |url| url.start_with?(prefix) }
    return unless matches.one? && prefix_identifies_resource?(prefix, matches.first)

    matches.first
  end

  def prefix_identifies_resource?(prefix, trusted_url)
    resource_url = URI.parse(trusted_url)
    return false if resource_url.path.blank? || resource_url.path == '/'

    resource_identity = trusted_url.split(/[?#]/, 2).first
    prefix.start_with?(resource_identity)
  rescue URI::InvalidURIError
    false
  end

  def replace_trailing_markdown(answer, match, replacement)
    "#{answer[0...match.begin(0)]}#{replacement}"
  end

  def sanitize_markdown_links(answer)
    answer.gsub(MARKDOWN_LINK_PATTERN) do
      match = Regexp.last_match
      normalized_url = normalize_url(match[:url])
      trusted_urls.include?(normalized_url) ? "[#{match[:label]}](#{normalized_url})" : match[:label]
    end
  end

  def sanitize_bare_urls(answer)
    answer.gsub(BARE_HTTP_URL_PATTERN) do |raw_url|
      normalized_url = normalize_url(raw_url)
      next normalized_url if trusted_urls.include?(normalized_url)

      url, punctuation = split_trailing_punctuation(raw_url)
      normalized_url = normalize_url(url)
      trusted_urls.include?(normalized_url) ? "#{normalized_url}#{punctuation}" : punctuation
    end
  end

  def split_trailing_punctuation(url)
    punctuation = url[/[.,;:!?]+\z/].to_s
    [url.delete_suffix(punctuation), punctuation]
  end

  def normalize_url(url)
    normalized = URI::DEFAULT_PARSER.escape(url.to_s, /[" <>\\()]/)
    uri = URI.parse(normalized)
    return unless uri.is_a?(URI::HTTP) && uri.host.present?

    normalized
  rescue URI::InvalidURIError
    nil
  end
end
