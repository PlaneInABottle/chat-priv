# frozen_string_literal: true

module IkasCatalogMvp
  module Text
    TURKISH_FOLD_MAP = {
      'ç' => 'c',
      'ğ' => 'g',
      'ı' => 'i',
      'ö' => 'o',
      'ş' => 's',
      'ü' => 'u',
      'Ç' => 'c',
      'Ğ' => 'g',
      'İ' => 'i',
      'I' => 'i',
      'Ö' => 'o',
      'Ş' => 's',
      'Ü' => 'u'
    }.freeze

    module_function

    def fold(value)
      value.to_s.each_char.map { |char| TURKISH_FOLD_MAP.fetch(char, char) }.join.downcase
           .gsub(/[^a-z0-9\s]/, ' ').squeeze(' ').strip
    end

    def tokens(value, min_length: 2)
      fold(value).split.select { |token| token.length >= min_length }
    end

    def json(value)
      JSON.generate(value)
    end
  end
end
