# frozen_string_literal: true

require 'cgi'

module IkasCatalogMvp
  class Normalizer
    SIZE_VALUES = %w[xxs xs s m l xl xxl xxxl].freeze
    COLOR_KEYS = %w[color colour renk].freeze
    SIZE_KEYS = %w[size beden numara].freeze
    ORGANIC_TERMS = %w[organic organik natural naturel dogal dogadan].freeze

    def initialize(categories:, variant_types:, product_attributes:, product_option_sets: [], storefronts: [])
      @categories = Array(categories)
      @variant_types = Array(variant_types)
      @product_attributes = Array(product_attributes)
      @product_option_sets = Array(product_option_sets)
      @product_link_builder = ProductLinkBuilder.new(storefronts: storefronts)
    end

    def product_visible?(product)
      product_link_builder.product_visible?(product)
    end

    def normalize_product(product)
      items = normalized_items(product)
      {
        group: group_for(product, items),
        items: items,
        facets: items.flat_map { |item| item.fetch('facets') },
        facts: items.flat_map { |item| item.fetch('facts') },
        categories: item_categories(product, items),
        group_categories: group_categories(product)
      }
    end

    private

    attr_reader :categories, :variant_types, :product_attributes, :product_option_sets, :product_link_builder

    def normalized_items(product)
      variants = Array(product['variants']).select { |variant| variant['isActive'] != false }
      variants = [nil] if variants.empty?
      variants.map { |variant| item_for(product, variant) }
    end

    def item_for(product, variant)
      variant_facets = variant ? variant_option_facets(product, variant) : []
      attribute_facets = product_attribute_facets(product)
      facets = dedupe_rows(variant_facets + attribute_facets) { |row| row.values_at('key', 'value') }
      name = display_name(product, variant_facets)
      stock = stock_for(product, variant)
      price = price_for(variant)
      search_text = search_text_for(product, name, facets)
      item = {
        'item_id' => variant ? "variant:#{variant.fetch('id')}" : "product:#{product.fetch('id')}",
        'group_id' => group_id(product),
        'product_id' => product.fetch('id'),
        'variant_id' => variant&.[]('id'),
        'entity_type' => variant ? 'variant' : 'product',
        'display_name' => name,
        'display_subtitle' => variant_facets.map { |facet| facet.fetch('value') }.join(' / '),
        'primary_category_id' => Array(product['categoryIds']).first,
        'price_amount' => price.fetch('amount'),
        'currency' => price.fetch('currency'),
        'stock_quantity' => stock.fetch('quantity'),
        'in_stock' => stock.fetch('in_stock') ? 1 : 0,
        'sellable' => stock.fetch('sellable') ? 1 : 0,
        'image_id' => image_id_for(variant),
        'search_text' => search_text,
        'search_text_folded' => Text.fold(search_text),
        'raw_json' => Text.json(variant || product)
      }.merge(product_link_builder.link_fields_for(product, option_facets: variant_facets))
      item['facets'] = facets.map { |facet| facet.merge('item_id' => item.fetch('item_id')) }
      item['facts'] = facts_for(product, variant, item, facets)
      item
    end

    def group_for(product, items)
      prices = items.filter_map { |item| item['price_amount'] }
      {
        'group_id' => group_id(product),
        'product_id' => product.fetch('id'),
        'display_name' => preferred_name(product),
        'primary_category_id' => Array(product['categoryIds']).first,
        'item_count' => items.length,
        'in_stock_count' => items.count { |item| item['in_stock'].to_i.positive? },
        'min_price_amount' => prices.min,
        'max_price_amount' => prices.max,
        'currency' => items.filter_map { |item| item['currency'] }.first,
        'search_text' => Text.fold(search_text_for(product, preferred_name(product), [])),
        'raw_json' => Text.json(product)
      }.merge(product_link_builder.link_fields_for(product))
    end

    def facts_for(product, variant, item, facets)
      rows = []
      rows << fact(item, 'stock', 'availability', item['in_stock'].to_i, nil, nil, 'stock', 'high', item['in_stock'].to_s)
      rows << fact(item, 'sellable', 'orderability', item['sellable'].to_i, nil, nil, 'stock', 'high', item['sellable'].to_s)
      rows << fact(item, 'price', 'price', item['price_amount'], nil, item['currency'], 'price', 'high', item['price_amount'].to_s) if item['price_amount']
      rows.concat(facet_facts(item, facets))
      rows.concat(text_facts(item, [item['display_name'], product['description'], product['shortDescription']].compact.join(' '), source: 'text', confidence: 'medium'))
      rows.concat(text_facts(item, product_attribute_text(product), source: 'product_attribute', confidence: 'high'))
      rows.concat(product_option_set_facts(item, product))
      rows.concat(weight_facts(item, product, variant))
      dedupe_rows(rows) { |row| row.values_at('type', 'key', 'value_text', 'numeric_value', 'numeric_value_2', 'unit', 'source') }
    end

    def facet_facts(item, facets)
      facets.flat_map do |facet|
        key = Text.fold(facet.fetch('key'))
        value = facet.fetch('value')
        rows = [fact(item, facet_type_for(key, value), facet.fetch('key'), nil, nil, nil, 'facet', facet.fetch('source') == 'product_attribute' ? 'high' : 'high', value)]
        rows << fact(item, 'organic', facet.fetch('key'), 1, nil, nil, 'facet', 'high', value) if organic_value?(value)
        rows
      end
    end

    def text_facts(item, text, source:, confidence:)
      text = clean_text(text)
      rows = []
      rows.concat(dimension_facts(item, text, source: source, confidence: confidence))
      rows.concat(weight_volume_facts(item, text, source: source, confidence: confidence))
      rows << fact(item, 'custom_size_supported', 'custom_size', 1, nil, nil, source, confidence, text) if custom_size?(text)
      rows << fact(item, 'organic', 'organic', 1, nil, nil, source, confidence, text) if organic_value?(text)
      rows
    end

    def dimension_facts(item, text, source:, confidence:)
      rows = []
      text.to_s.scan(max_dimension_regex) do |raw, _a, _b, unit|
        values = dimension_values(raw, unit)
        rows << fact(item, 'dimension_max', 'dimension', values[0], values[1], normalized_unit(unit), source, confidence, raw)
      end
      consumed = text.to_s.gsub(max_dimension_regex, ' ')
      consumed.scan(range_regex) do |raw, _number_a, unit_a, _number_b, unit_b|
        unit = unit_a || unit_b
        next unless unit

        values = dimension_values(raw, unit)
        rows << fact(item, 'dimension_range', 'dimension', values[0], values[1], normalized_unit(unit), source, confidence, raw)
      end
      consumed.gsub(range_regex, ' ').scan(pair_regex) do |raw, _unit|
        values = dimension_values(raw, raw[/\b(cm|mm|m)\b/i])
        rows << fact(item, 'dimension_exact', 'dimension', values[0], values[1], normalized_unit(raw[/\b(cm|mm|m)\b/i]), source, confidence, raw)
      end
      rows
    end

    def weight_volume_facts(item, text, source:, confidence:)
      rows = []
      text.to_s.scan(/((\d+(?:[,.]\d+)?)\s*(kg|gr|g)\b)/i) do |raw, number, unit|
        value = number.tr(',', '.').to_f
        rows << fact(item, 'weight', 'weight', unit.downcase == 'kg' ? value * 1000 : value, nil, 'g', source, confidence, raw)
      end
      text.to_s.scan(/((\d+(?:[,.]\d+)?)\s*(ml|lt|l)\b)/i) do |raw, number, unit|
        value = number.tr(',', '.').to_f
        rows << fact(item, 'volume', 'volume', %w[l lt].include?(unit.downcase) ? value * 1000 : value, nil, 'ml', source, confidence, raw)
      end
      rows
    end

    def product_option_set_facts(item, product)
      option_set = product_option_set_lookup[product['productOptionSetId']]
      return [] unless option_set

      dimensions = option_set_dimensions(option_set)
      rows = dimensions.empty? ? [] : [fact(item, 'dimension_max', 'product_option_set', dimensions[0], dimensions[1], 'cm', 'product_option_set', 'high', option_set.fetch('name'))]
      rows << fact(item, 'custom_size_supported', 'product_option_set', 1, nil, nil, 'product_option_set', 'high', option_set.fetch('name')) if dimensions.any?
      rows
    end

    def option_set_dimensions(option_set)
      dimension_options = Array(option_set['options']).filter_map do |option|
        max = option.dig('textSettings', 'max')
        next unless max

        key = dimension_option_key(option['name'])
        next unless key

        [key, max.to_f]
      end.to_h
      width = dimension_options['width']
      height = dimension_options['height']
      width && height ? [width, height] : []
    end

    def dimension_option_key(name)
      folded = Text.fold(name)
      return 'width' if folded.match?(/\b(en|width)\b/)
      return 'height' if folded.match?(/\b(boy|height)\b/)

      nil
    end

    def weight_facts(item, product, _variant)
      return [] unless product['weight'].is_a?(Numeric)

      [fact(item, 'weight', 'product_weight', product['weight'], nil, nil, 'product', 'high', product['weight'].to_s)]
    end

    def fact(item, type, key, numeric_value, numeric_value_2, unit, source, confidence, raw)
      value_text = [numeric_value, numeric_value_2].compact.join('x')
      raw_text = clean_text(raw)
      value_text = raw_text if value_text.empty? && raw
      {
        'item_id' => item.fetch('item_id'),
        'type' => type,
        'key' => key,
        'value_text' => value_text,
        'value_folded' => Text.fold(value_text),
        'numeric_value' => numeric_value,
        'numeric_value_2' => numeric_value_2,
        'unit' => unit,
        'source' => source,
        'confidence' => confidence,
        'raw' => raw_text[0, 300]
      }
    end

    def product_attribute_facets(product)
      Array(product['attributes']).filter_map do |attribute_value|
        definition = product_attribute_lookup[attribute_value['productAttributeId']]
        next unless definition

        option = product_attribute_option_lookup[attribute_value['productAttributeOptionId']]
        value = attribute_value['value'].to_s.empty? ? option&.[]('name') : attribute_value['value']
        next if value.to_s.empty?

        { 'key' => definition.fetch('name'), 'value' => value.to_s, 'source' => 'product_attribute' }
      end
    end

    def product_attribute_text(product)
      product_attribute_facets(product).map { |facet| "#{facet.fetch('key')} #{facet.fetch('value')}" }.join(' ')
    end

    def variant_option_facets(product, variant)
      Array(variant['variantValueIds']).filter_map do |relation|
        type = variant_type_lookup[relation['variantTypeId']]
        value = variant_value_lookup[relation['variantValueId']]
        next unless type && value

        { 'key' => type.fetch('name'), 'value' => value.fetch('name'), 'source' => 'variant_type', 'product_id' => product.fetch('id') }
      end
    end

    def display_name(product, variant_facets)
      subtitle = variant_facets.map { |facet| facet.fetch('value') }.join(' / ')
      [preferred_name(product), subtitle.empty? ? nil : subtitle].compact.join(' - ')
    end

    def preferred_name(product)
      translations = Array(product['translations'])
      tr_name = translations.find { |row| row['locale'].to_s.downcase == 'tr' }&.[]('name')
      en_name = translations.find { |row| row['locale'].to_s.downcase == 'en' }&.[]('name')
      tr_name.to_s.empty? ? (product['name'] || en_name).to_s : tr_name
    end

    def search_text_for(product, name, facets)
      [
        name,
        product['name'],
        clean_text(product['description']),
        clean_text(product['shortDescription']),
        Array(product['translations']).flat_map { |row| [row['name'], clean_text(row['description'])] },
        category_names(product),
        Array(product['tags']).map { |tag| tag['name'] },
        facets.map { |facet| [facet['key'], facet['value']] }
      ].flatten.compact.uniq.join(' ')
    end

    def category_names(product)
      Array(product['categoryIds']).filter_map { |id| category_lookup[id]&.[]('name') }
    end

    def item_categories(product, items)
      items.flat_map do |item|
        Array(product['categoryIds']).map { |category_id| { 'item_id' => item.fetch('item_id'), 'category_id' => category_id } }
      end
    end

    def group_categories(product)
      Array(product['categoryIds']).map { |category_id| { 'group_id' => group_id(product), 'category_id' => category_id } }
    end

    def group_id(product)
      "product:#{product.fetch('id')}"
    end

    def price_for(variant)
      price = Array(variant&.[]('prices')).find { |row| row['sellPrice'] }
      { 'amount' => price&.[]('sellPrice'), 'currency' => price&.[]('currencyCode') || price&.[]('currency') }
    end

    def stock_for(product, variant)
      quantities = Array(variant&.[]('stocks')).filter_map { |row| row['stockCount'] }
      quantity = quantities.empty? ? product['totalStock'] : quantities.sum
      in_stock = quantity.to_f.positive?
      sellable = in_stock || variant&.[]('sellIfOutOfStock') == true
      { 'quantity' => quantity, 'in_stock' => in_stock, 'sellable' => sellable }
    end

    def image_id_for(variant)
      image = Array(variant&.[]('images')).find { |row| row['isMain'] } || Array(variant&.[]('images')).first
      image&.[]('imageId')
    end

    def facet_type_for(key, value)
      return 'color' if COLOR_KEYS.include?(key)
      return 'size' if SIZE_KEYS.include?(key) || SIZE_VALUES.include?(Text.fold(value))

      'facet'
    end

    def organic_value?(value)
      (Text.tokens(value) & ORGANIC_TERMS).any?
    end

    def custom_size?(value)
      Text.fold(value).match?(/\b(custom size|ozel olcu|ozel ebat|istedigin olcude|istediginiz olcude|customizable)\b/)
    end

    def clean_text(value)
      CGI.unescapeHTML(value.to_s.gsub(/<[^>]*>/, ' ')).squeeze(' ').strip
    end

    def max_dimension_regex
      /((?:max(?:imum)?|maks(?:imum)?|en\s+fazla|up\s+to)\s*[:.\-]?\s*(\d+(?:[,.]\d+)?)\s*[x×*]\s*(\d+(?:[,.]\d+)?)(?:\s*(cm|mm|m))?)/i
    end

    def range_regex
      /((\d+(?:[,.]\d+)?)(?:\s*(cm|mm|m))?\s*(?:-+|–|araligi|aralığında|range|to)\s*(\d+(?:[,.]\d+)?)(?:\s*(cm|mm|m))?)/i
    end

    def pair_regex
      /((?:\d+(?:[,.]\d+)?)\s*[x×*]\s*(?:\d+(?:[,.]\d+)?)(?:\s*(cm|mm|m))?)/i
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
      unit.to_s.empty? ? 'cm' : (unit.downcase == 'mm' || unit.downcase == 'm' ? 'cm' : unit.downcase)
    end

    def dedupe_rows(rows)
      seen = {}
      rows.each_with_object([]) do |row, result|
        key = yield(row)
        next if seen[key]

        seen[key] = true
        result << row
      end
    end

    def category_lookup
      @category_lookup ||= categories.each_with_object({}) { |row, memo| memo[row['id']] = row }
    end

    def variant_type_lookup
      @variant_type_lookup ||= variant_types.each_with_object({}) { |row, memo| memo[row['id']] = row }
    end

    def variant_value_lookup
      @variant_value_lookup ||= variant_types.flat_map { |row| Array(row['values']) }.each_with_object({}) { |row, memo| memo[row['id']] = row }
    end

    def product_attribute_lookup
      @product_attribute_lookup ||= product_attributes.each_with_object({}) { |row, memo| memo[row['id']] = row }
    end

    def product_attribute_option_lookup
      @product_attribute_option_lookup ||= product_attributes.flat_map { |row| Array(row['options']) }.each_with_object({}) { |row, memo| memo[row['id']] = row }
    end

    def product_option_set_lookup
      @product_option_set_lookup ||= product_option_sets.each_with_object({}) { |row, memo| memo[row['id']] = row }
    end
  end
end
