# frozen_string_literal: true

module IkasCatalogMvp
  class QueryParser
    SIZE_VALUES = %w[xxs xs s m l xl xxl xxxl].freeze
    INTENT_TOKENS = %w[
      ariyorum arastiriyorum bakiyorum istiyorum lazim gerekiyor
      verir verebilir ver misin musun
      looking look need want show browse give
    ].freeze
    NOISE_TOKENS = %w[
      icin for olan var mi varmidir urun product
      ne nedir hangi hangisi link linki url adres baglanti
    ].freeze
    ORGANIC_TOKENS = %w[organic organik natural naturel dogal].freeze
    SIZE_ALIASES = {
      'small' => 's',
      'medium' => 'm',
      'large' => 'l'
    }.freeze

    def initialize(facet_vocabulary: {})
      @facet_vocabulary = facet_vocabulary
    end

    def self.terms_for(query, facet_vocabulary: {})
      new(facet_vocabulary: facet_vocabulary).parse(query).fetch('terms')
    end

    def parse(query)
      working = query.to_s.dup
      constraints = []
      unsupported = []

      constraints.concat(extract_dimensions!(working))
      constraints.concat(extract_weight_volume!(working))
      constraints.concat(extract_price!(working))
      constraints.concat(extract_stock!(working))
      constraints.concat(extract_custom_size!(working))
      constraints.concat(extract_size!(working))
      constraints.concat(extract_organic!(working))
      constraints.concat(extract_facets!(working))
      unsupported.concat(detect_unknown_color!(working))

      {
        'terms' => remaining_terms(working),
        'constraints' => constraints.compact,
        'unsupported_constraints' => unsupported
      }
    end

    private

    attr_reader :facet_vocabulary

    def extract_dimensions!(text)
      rows = []
      text.scan(pair_regex).each do |raw, unit|
        text.sub!(raw, ' ')
        rows << { 'type' => 'dimension_pair', 'values' => dimension_values(raw, unit), 'unit' => normalized_unit(unit), 'raw' => raw.strip }
      end
      rows
    end

    def pair_regex
      /((?:\d+(?:[,.]\d+)?)\s*[x×*]\s*(?:\d+(?:[,.]\d+)?)(?:\s*(cm|mm|m))?)/i
    end

    def extract_weight_volume!(text)
      rows = []
      text.scan(/((\d+(?:[,.]\d+)?)\s*(kg|gr|g)\b)/i).each do |raw, number, unit|
        text.sub!(raw, ' ')
        value = number.tr(',', '.').to_f
        rows << { 'type' => 'weight', 'operator' => 'eq', 'value' => unit.downcase == 'kg' ? value * 1000 : value, 'unit' => 'g', 'raw' => raw.strip }
      end
      text.scan(/((\d+(?:[,.]\d+)?)\s*(ml|lt|l)\b)/i).each do |raw, number, unit|
        text.sub!(raw, ' ')
        value = number.tr(',', '.').to_f
        rows << { 'type' => 'volume', 'operator' => 'eq', 'value' => %w[l lt].include?(unit.downcase) ? value * 1000 : value, 'unit' => 'ml', 'raw' => raw.strip }
      end
      rows
    end

    def extract_price!(text)
      rows = []
      text.scan(/((?:under|max|alt[ıi])\s*(\d+(?:[,.]\d+)?)|(\d+(?:[,.]\d+)?)\s*(?:tl|try)\s*(?:alt[ıi]|kadar|under)?)/i).each do |raw, number_a, number_b|
        text.sub!(raw, ' ')
        number = number_a || number_b
        rows << { 'type' => 'price', 'operator' => 'lte', 'value' => number.tr(',', '.').to_f, 'unit' => 'TRY', 'raw' => raw.strip }
      end
      rows
    end

    def extract_stock!(text)
      rows = []
      text.scan(/\b(stokta|mevcut|in stock|available)\b/i).each do |raw|
        text.sub!(raw.first, ' ')
        rows << { 'type' => 'stock', 'operator' => 'eq', 'value' => true, 'raw' => raw.first }
      end
      rows
    end

    def extract_custom_size!(text)
      return [] unless Text.fold(text).match?(/\b(custom size|ozel olcu|ozel ebat|istedigin olcude|istediginiz olcude|customizable)\b/)

      text.gsub!(/custom\s*size|özel\s*ölçü|özel\s*ebat|istediğin\s*ölçüde|istediğiniz\s*ölçüde|customizable/i, ' ')
      [{ 'type' => 'custom_size_requested', 'operator' => 'eq', 'value' => true, 'raw' => 'custom_size' }]
    end

    def extract_size!(text)
      rows = []
      text.scan(/\b(#{(SIZE_VALUES + SIZE_ALIASES.keys).join('|')})\b/i).each do |raw|
        value = SIZE_ALIASES.fetch(raw.first.downcase, raw.first.downcase)
        next if value == 'm' && text.match?(/\d+\s*m\b/i)

        text.sub!(/\b#{Regexp.escape(raw.first)}\b/i, ' ')
        rows << { 'type' => 'size', 'operator' => 'eq', 'value' => value, 'raw' => raw.first }
      end
      rows
    end

    def extract_organic!(text)
      found = Text.tokens(text) & ORGANIC_TOKENS
      return [] if found.empty?

      text.gsub!(/\b(?:organic|organik|natural|naturel|doğal|dogal)\b/i, ' ')
      [{ 'type' => 'organic', 'operator' => 'eq', 'value' => true, 'raw' => found.join(' ') }]
    end

    def extract_facets!(text)
      vocabulary_entries.filter_map do |entry|
        next unless phrase_present?(text, entry.fetch('value_folded'))

        text.gsub!(/#{Regexp.escape(entry.fetch('value'))}/i, ' ')
        {
          'type' => entry.fetch('fact_type'),
          'operator' => 'eq',
          'key' => entry.fetch('key'),
          'value' => entry.fetch('value'),
          'raw' => entry.fetch('value')
        }
      end
    end

    def vocabulary_entries
      facet_vocabulary.flat_map do |key, values|
        folded_key = Text.fold(key)
        Array(values).map do |value|
          {
            'key' => key,
            'value' => value,
            'value_folded' => Text.fold(value),
            'fact_type' => FacetKeyClassifier.color?(folded_key) ? 'color' : 'facet'
          }
        end
      end
    end

    def detect_unknown_color!(text)
      color_words = %w[beyaz siyah kirmizi kırmızı mavi yesil yeşil sari sarı gri grey gray black white red blue green yellow]
      known = vocabulary_entries.select { |entry| entry.fetch('fact_type') == 'color' }.map { |entry| entry.fetch('value_folded') }
      (Text.tokens(text) & color_words.map { |word| Text.fold(word) }).reject { |token| known.include?(token) }
        .map { |token| { 'type' => 'unknown_color', 'value' => token, 'reason' => 'not_found_in_catalog_facets' } }
    end

    def phrase_present?(text, folded_phrase)
      folded = " #{Text.fold(text)} "
      folded.include?(" #{folded_phrase} ")
    end

    def remaining_terms(text)
      Text.tokens(text, min_length: 2).reject { |token| INTENT_TOKENS.include?(token) || NOISE_TOKENS.include?(token) }
    end

    def dimension_values(raw, unit)
      raw.to_s.scan(/\d+(?:[,.]\d+)?/).first(2).map { |value| normalize_dimension_value(value, unit) }
    end

    def normalize_dimension_value(value, unit)
      numeric = value.tr(',', '.').to_f
      case unit.to_s.downcase
      when 'mm' then numeric / 10.0
      when 'm' then numeric * 100.0
      else numeric
      end
    end

    def normalized_unit(unit)
      unit.to_s.empty? ? 'cm' : 'cm'
    end
  end
end
