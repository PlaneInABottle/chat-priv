# frozen_string_literal: true

class AiKnowledgeSources::Retriever
  DEFAULT_LIMIT = 3
  MAX_LIMIT = 5
  MAX_QUERY_LENGTH = 240
  EXCERPT_LENGTH = 480
  SEGMENT_LENGTH = 900
  MIN_RELEVANCE_SCORE = 40
  STOP_WORDS = %w[
    a an and are as at be by for from how in is it of on or that the this to what when where which who why with
    ama bir bu da de gibi icin ile mi mu nasil ne neden nerede ve veya
  ].freeze

  def initialize(sources:)
    @sources = Array(sources).map { |source| source.to_h.deep_stringify_keys }
  end

  def call(query:, limit: DEFAULT_LIMIT)
    normalized_query = query.to_s.strip.truncate(MAX_QUERY_LENGTH, omission: '')
    query_tokens = tokens(normalized_query)
    return invalid_query_payload if query_tokens.empty?

    matches = ranked_matches(query_tokens, normalized_query).first(normalized_limit(limit))
    {
      status: 'ok',
      result_type: matches.any? ? 'matches' : 'no_match',
      query: normalized_query,
      result_count: matches.length,
      matches: matches,
      attributions: matches.map { |match| match.slice(:source_id, :source_name) }
    }
  end

  private

  attr_reader :sources

  def ranked_matches(query_tokens, query)
    sources.filter_map { |source| scored_source(source, query_tokens, query) }
           .sort_by { |match| [-match[:score], match[:source_id].to_i] }
           .map { |match| match.except(:score) }
  end

  def scored_source(source, query_tokens, query)
    source_tokens = tokens("#{source['name']} #{source['content']}")
    matched_tokens = query_tokens & source_tokens
    return if matched_tokens.empty?

    score = relevance_score(source, query_tokens, matched_tokens, query)
    return if score < MIN_RELEVANCE_SCORE

    {
      source_id: source['id'],
      source_name: source['name'].to_s,
      excerpt: best_excerpt(source['content'].to_s, matched_tokens),
      score: score
    }
  end

  def relevance_score(source, query_tokens, matched_tokens, query)
    coverage = matched_tokens.length.fdiv(query_tokens.length)
    name_tokens = tokens(source['name'])
    name_matches = (matched_tokens & name_tokens).length
    phrase_bonus = normalized_text("#{source['name']} #{source['content']}").include?(normalized_text(query)) ? 25 : 0

    (coverage * 100) + (name_matches * 12) + phrase_bonus
  end

  def best_excerpt(content, matched_tokens)
    segments = content.scan(/.{1,#{SEGMENT_LENGTH}}(?:\s+|\z)/mo)
    segments = [content] if segments.empty?
    best_segment = segments.max_by do |segment|
      segment_tokens = tokens(segment)
      matched_tokens.sum { |token| [segment_tokens.count(token), 3].min }
    end
    best_segment.to_s.squish.truncate(EXCERPT_LENGTH, separator: ' ')
  end

  def tokens(text)
    normalized_text(text).scan(/[\p{L}\p{N}]{2,}/).uniq - STOP_WORDS
  end

  def normalized_text(text)
    text.to_s.unicode_normalize(:nfkd).downcase.gsub(/\p{Mn}/, '')
  end

  def normalized_limit(limit)
    parsed = Integer(limit, exception: false) || DEFAULT_LIMIT
    parsed.clamp(1, MAX_LIMIT)
  end

  def invalid_query_payload
    {
      status: 'error',
      error_code: 'invalid_query',
      error_message: 'Knowledge query cannot be blank.'
    }
  end
end
