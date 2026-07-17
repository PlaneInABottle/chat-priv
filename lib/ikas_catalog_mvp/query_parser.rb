# frozen_string_literal: true

module IkasCatalogMvp
  class QueryParser
    def initialize(facet_vocabulary: {})
      @facet_vocabulary = facet_vocabulary
    end

    def self.terms_for(query, facet_vocabulary: {})
      new(facet_vocabulary: facet_vocabulary).parse(query).fetch('terms')
    end

    def parse(query)
      working = query.to_s.dup
      constraints = []

      constraints.concat(extract_dimensions!(working))
      constraints.concat(extract_weight_volume!(working))
      constraints.concat(extract_facets!(working))

      {
        'terms' => Text.tokens(working, min_length: 2),
        'constraints' => constraints,
        'unsupported_constraints' => []
      }
    end

    private

    attr_reader :facet_vocabulary

    def extract_dimensions!(text)
      rows = []
      text.scan(pair_regex).each do |raw, unit|
        text.sub!(raw, ' ')
        rows << { 'type' => 'dimension_pair', 'values' => dimension_values(raw, unit), 'unit' => 'cm', 'raw' => raw.strip }
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

    def extract_facets!(text)
      folded_text = Text.fold(text)
      vocabulary_entries.filter_map do |entry|
        next unless phrase_present?(folded_text, entry.fetch('value_folded'))

        text.gsub!(/#{Regexp.escape(entry.fetch('value'))}/i, ' ')
        folded_text = Text.fold(text)
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
      @vocabulary_entries ||= facet_vocabulary.flat_map do |key, values|
        Array(values).map do |value|
          {
            'key' => key,
            'value' => value,
            'value_folded' => Text.fold(value),
            'fact_type' => 'facet'
          }
        end
      end
    end

    def phrase_present?(folded_text, folded_phrase)
      " #{folded_text} ".include?(" #{folded_phrase} ")
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
  end
end
