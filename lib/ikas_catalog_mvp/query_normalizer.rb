# frozen_string_literal: true

module IkasCatalogMvp::QueryNormalizer
  CONTEXTUAL_LOCATION_TOKENS = %w[
    balcony balkon bathroom banyo bedroom kitchen living mutfak oda odasi office ofis
    patio room salon terrace teras veranda yatak
  ].freeze
  OPENING_TOKEN_PATTERNS = [
    /\Akapi(?:si(?:n(?:a|da|dan)?|ni)?|yi|ya|da|dan|nin|lar(?:i)?)?\z/,
    /\Apencere(?:si(?:n(?:e|de|den)?|ni)?|yi|ye|de|den|nin|ler(?:i)?)?\z/,
    /\A(?:door|window)s?\z/
  ].freeze

  module_function

  def contextual_location_fallback(query, parsed)
    terms = parsed.fetch('terms').dup
    contextual_location_terms(query).each do |location_term|
      index = terms.index(location_term)
      terms.delete_at(index) if index
    end
    return if terms == parsed.fetch('terms') || terms.length < 2

    parsed.merge('terms' => terms)
  end

  def contextual_location_terms(query)
    tokens = IkasCatalogMvp::Text.tokens(query)
    tokens.each_index.with_object([]) do |index, terms|
      next unless opening_token?(tokens[index])

      location_index = index - 1
      while location_index >= 0 && CONTEXTUAL_LOCATION_TOKENS.include?(tokens[location_index])
        terms << tokens[location_index]
        location_index -= 1
      end
    end
  end

  def opening_token?(token)
    OPENING_TOKEN_PATTERNS.any? { |pattern| pattern.match?(token) }
  end
end
