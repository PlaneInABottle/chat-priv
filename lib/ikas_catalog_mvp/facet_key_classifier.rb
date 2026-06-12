# frozen_string_literal: true

module IkasCatalogMvp
  module FacetKeyClassifier
    COLOR_KEYS = %w[color colour renk rengi].freeze
    SIZE_KEYS = %w[size beden numara].freeze

    module_function

    def color?(key)
      folded = Text.fold(key)
      # Ikas sellers often use descriptive option keys such as "Perde Rengi";
      # substring matching keeps those structured variant values usable as color facts.
      COLOR_KEYS.any? { |color_key| folded == color_key || folded.include?(color_key) }
    end

    def size?(key)
      folded = Text.fold(key)
      SIZE_KEYS.any? { |size_key| folded == size_key || folded.include?(size_key) }
    end
  end
end
