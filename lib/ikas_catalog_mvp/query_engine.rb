# frozen_string_literal: true

require 'active_support/core_ext/enumerable'

require 'sqlite3'

module IkasCatalogMvp
  class QueryEngine
    DEFAULT_LIMIT = 8
    BROAD_CLARIFICATION_BUCKET_LIMIT = 8
    CONSTRAINED_CLARIFICATION_BUCKET_LIMIT = 3
    CHILD_BUCKET_LIMIT = 5
    SEARCH_BACKEND = 'fts5'.freeze
    STRUCTURED_EVIDENCE_SOURCES = %w[facet product_attribute product_option_set product price stock].freeze

    def initialize(sqlite_path:)
      @sqlite_path = sqlite_path
    end

    def query(text, limit: DEFAULT_LIMIT)
      with_db do |db|
        parsed = query_parser(db).parse(text)
        return needs_scope_payload(text, parsed) if scope_required?(db, parsed)
        return unsupported_payload(text, parsed) if parsed.fetch('unsupported_constraints').any?

        root = matched_root(db, category_scope_terms_for(db, parsed))
        buckets = root ? type_buckets(db, root.fetch('id')) : []
        if clarification_needed?(parsed, buckets)
          return clarify_payload(text, parsed, root, buckets)
        end

        root_category_ids = root ? category_subtree_ids(db, root.fetch('id')) : []
        candidates = candidates_for(db, parsed, root, root_category_ids, limit)
        constrained_clarification = constrained_clarification_payload(db, text, parsed, root, candidates)
        return constrained_clarification if constrained_clarification

        result_payload(text, parsed, root, candidates)
      end
    end

    private

    attr_reader :sqlite_path

    def query_parser(db)
      QueryParser.new(facet_vocabulary: facet_vocabulary(db))
    end

    def needs_scope_payload(text, parsed)
      {
        'result_type' => 'needs_scope',
        'query' => text,
        'parsed' => parsed,
        'candidates' => [],
        'search_backend' => SEARCH_BACKEND,
        'warnings' => ['query_missing_catalog_scope'],
        'next_action' => 'ask_customer_which_product_or_category'
      }
    end

    def scope_required?(db, parsed)
      parsed.fetch('constraints').any? && scope_terms_for(db, parsed).empty?
    end

    def scope_terms_for(db, parsed)
      parsed.fetch('terms').select { |term| catalog_scope_term?(db, term) }
    end

    def clarification_needed?(parsed, buckets)
      parsed.fetch('constraints').empty? && buckets.length > 1
    end

    def constrained_clarification_payload(db, text, parsed, root, candidates)
      return unless root && parsed.fetch('constraints').any? && candidates.length > 1

      buckets = type_buckets(db, root.fetch('id'))
      counts = candidates.filter_map { |candidate| candidate_bucket_id(db, candidate.fetch('product_id'), buckets) }.tally
      return if counts.length < 2

      surviving = buckets.filter_map do |bucket|
        count = counts[bucket.fetch('category_id')]
        bucket.merge('group_count' => count) if count
      end.sort_by { |bucket| [-bucket.fetch('group_count'), bucket.fetch('label')] }
      clarify_payload(text, parsed, root, surviving, bucket_limit: CONSTRAINED_CLARIFICATION_BUCKET_LIMIT)
    end

    def clarify_payload(text, parsed, root, buckets, bucket_limit: BROAD_CLARIFICATION_BUCKET_LIMIT)
      visible_buckets = buckets.first(bucket_limit)
      payload = {
        'result_type' => 'clarify_category',
        'query' => text,
        'parsed' => parsed,
        'matched_scope' => root,
        'buckets' => visible_buckets,
        'search_backend' => SEARCH_BACKEND,
        'next_action' => 'ask_customer_to_choose_category_or_type'
      }
      omitted_count = buckets.length - visible_buckets.length
      payload['buckets_omitted'] = omitted_count if omitted_count.positive?
      payload
    end

    def unsupported_payload(text, parsed)
      {
        'result_type' => 'unsupported',
        'query' => text,
        'parsed' => parsed,
        'candidates' => [],
        'search_backend' => SEARCH_BACKEND,
        'warnings' => ['query_contains_constraints_not_present_in_catalog_vocabulary']
      }
    end

    def result_payload(text, parsed, root, candidates)
      type = if candidates.empty?
               'no_match'
             elsif candidates.any? { |candidate| candidate.fetch('match_kind') == 'compatible' }
               'show_compatible_candidates'
             else
               'show_candidates'
             end

      {
        'result_type' => type,
        'query' => text,
        'parsed' => parsed,
        'matched_scope' => root,
        'result_count' => candidates.length,
        'candidates' => candidates,
        'search_backend' => SEARCH_BACKEND,
        'warnings' => []
      }
    end

    def matching_rows(db, parsed, root, limit, category_ids:)
      terms = search_terms_for(db, root, parsed.fetch('terms'))
      fts5_terms = fts5_terms_for(terms)
      return category_matching_rows(db, limit, category_ids: category_ids) if fts5_terms.empty?

      raise Error, 'Ikas catalog FTS index is missing. Sync the catalog again.' unless fts5_available?(db)

      rows = fts5_matching_rows(db, fts5_terms, limit, category_ids: category_ids)
      return rows if rows.any? || fts5_terms.length < 3

      relaxed_fts5_matching_rows(db, fts5_terms, limit, category_ids: category_ids)
    end

    def candidates_for(db, parsed, root, root_category_ids, limit)
      rows = matching_rows(db, parsed, root, limit, category_ids: root_category_ids)
      rows = matching_rows(db, parsed, nil, limit, category_ids: []) if rows.empty? && root
      candidates = rows.filter_map { |row| candidate_for(db, row, parsed, root, root_category_ids) }
      rescue_terms = exact_phrase_rescue_terms(parsed, root, candidates)
      candidates.concat(exact_phrase_rescued_candidates(db, parsed, limit, rescue_terms)) if rescue_terms
      sorted_candidates = candidates.sort_by do |candidate|
        [
          rescue_terms && rescued_display_name_candidate?(candidate, rescue_terms) ? 0 : 1,
          candidate_sort_key(candidate, parsed.fetch('terms'))
        ]
      end
      grouped = grouped_candidates(db, sorted_candidates)
      grouped = prefer_minimally_qualified_candidates(grouped, parsed.fetch('terms')) if parsed.fetch('constraints').empty?
      grouped.first(limit)
    end

    # When the matched root scope returns only sibling-family candidates that do
    # not start with the full folded query phrase (for example the scope matched
    # "Double Akordiyon Pencere Sineklikleri" for the query "Akordeon Pencere
    # Sineklik"), search the whole catalog for display-name matches that cover
    # every requested term, regardless of order or small spelling differences.
    def exact_phrase_rescue_terms(parsed, root, candidates)
      terms = parsed.fetch('terms')
      return nil if root.nil? || candidates.empty? || terms.length < 3

      phrase = Text.fold(terms.join(' '))
      return nil if candidates.any? { |candidate| display_name_starts_with_phrase?(candidate, phrase) }

      terms
    end

    def exact_phrase_rescued_candidates(db, parsed, limit, terms)
      fts5_terms = fts5_terms_for(search_terms_for(db, nil, parsed.fetch('terms')))
      raise Error, 'Ikas catalog FTS index is missing. Sync the catalog again.' unless fts5_available?(db)

      rows = relaxed_fts5_matching_rows(db, fts5_terms, limit * 2, category_ids: [])
      rows.filter_map { |row| candidate_for(db, row, parsed, nil, []) }
          .select { |candidate| rescued_display_name_candidate?(candidate, terms) }
    end

    def rescued_display_name_candidate?(candidate, terms)
      display_name_tokens = Text.tokens(candidate.fetch('display_name'))
      terms.all? { |term| display_name_tokens.any? { |token| category_token_match?(term, token) } }
    end

    def display_name_starts_with_phrase?(candidate, phrase)
      Text.fold(candidate.fetch('display_name')).start_with?(phrase)
    end

    def prefer_minimally_qualified_candidates(candidates, terms)
      fully_matching = candidates.select { |candidate| visible_term_miss_count(candidate.fetch('display_name'), terms).zero? }
      return candidates if fully_matching.length < 2
      return candidates if fully_matching.map { |candidate| candidate.fetch('category_paths') }.uniq.length < 2
      category_depths = fully_matching.map do |candidate|
        candidate.fetch('category_paths').map { |path| path.split(' > ').length }.max
      end
      return candidates if category_depths.uniq.length > 1

      minimum_extra_tokens = fully_matching.map { |candidate| unmatched_display_name_token_count(candidate.fetch('display_name'), terms) }.min
      candidates.reject do |candidate|
        fully_matching.include?(candidate) && unmatched_display_name_token_count(candidate.fetch('display_name'), terms) > minimum_extra_tokens
      end
    end

    def unmatched_display_name_token_count(display_name, terms)
      Text.tokens(display_name).count do |token|
        terms.none? { |term| category_token_match?(term, token) }
      end
    end

    def category_matching_rows(db, limit, category_ids:)
      sql = category_matching_rows_sql(category_ids)
      bindings = category_ids.dup
      bindings << product_pool_limit(limit)
      db.execute(sql, bindings)
    end

    def fts5_available?(db)
      db.get_first_value("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'catalog_items_fts'").to_s != ''
    end

    def fts5_matching_rows(db, fts5_terms, limit, category_ids:, operator: 'AND')
      bindings = [fts5_query_for(fts5_terms, operator: operator)]
      bindings.concat(category_ids)
      matched_rows = db.execute(fts5_matching_rows_sql(category_ids), bindings)
      product_scores = matched_rows.group_by { |row| row.fetch('product_id') }.transform_values do |rows|
        rows.filter_map { |row| row['fts_score'] }.min
      end
      product_ids = product_scores.keys.first(product_pool_limit(limit))
      return [] if product_ids.empty?

      db.execute(
        "SELECT * FROM catalog_items WHERE product_id IN (#{placeholders(product_ids)})",
        product_ids
      ).each { |row| row['fts_score'] = product_scores[row.fetch('product_id')] }
        .sort_by { |row| [row['fts_score'].to_f, -row.fetch('sellable').to_i, row['price_amount'] || Float::INFINITY, row.fetch('display_name')] }
    end

    def product_pool_limit(limit)
      [limit.to_i * 8, 50].max
    end

    def relaxed_fts5_matching_rows(db, fts5_terms, limit, category_ids:)
      fts5_matching_rows(db, fts5_terms, limit, category_ids: category_ids, operator: 'OR').select do |row|
        sufficient_query_term_coverage?(row, fts5_terms)
      end
    end

    def sufficient_query_term_coverage?(row, terms)
      searchable_tokens = Text.tokens(row.fetch('search_text_folded'))
      unique_terms = terms.uniq
      matched_count = unique_terms.count do |term|
        searchable_tokens.any? { |token| category_token_match?(term, token) }
      end

      matched_count >= 2 && matched_count * 2 > unique_terms.length
    end

    def fts5_matching_rows_sql(category_ids)
      clauses = ['catalog_items_fts MATCH ?']
      clauses << "ic.category_id IN (#{placeholders(category_ids)})" if category_ids.any?
      join_sql = category_ids.any? ? 'INNER JOIN catalog_item_categories ic ON ic.item_id = i.item_id' : ''

      <<~SQL
        SELECT DISTINCT i.product_id, bm25(catalog_items_fts, 0.0, 10.0, 1.0) AS fts_score
        FROM catalog_items_fts
        INNER JOIN catalog_items i ON i.item_id = catalog_items_fts.item_id
        #{join_sql}
        WHERE #{clauses.join(' AND ')}
        ORDER BY fts_score ASC
      SQL
    end

    def fts5_query_for(fts5_terms, operator: 'AND')
      fts5_terms.map { |term| fts5_term_query(term) }.join(" #{operator} ")
    end

    def fts5_term_query(term)
      escaped = term.gsub('"', '""')
      return %("#{escaped}") if term.length <= 3
      return %("#{escaped}"*) if term.length <= 5

      %("#{escaped}")
    end

    def fts5_terms_for(terms)
      terms.map { |term| Text.fold(term) }.reject(&:empty?)
    end

    def category_matching_rows_sql(category_ids)
      clauses = []
      clauses << "ic.category_id IN (#{placeholders(category_ids)})" if category_ids.any?
      where_sql = clauses.empty? ? '1 = 1' : clauses.join(' AND ')
      join_sql = category_ids.any? ? 'INNER JOIN catalog_item_categories ic ON ic.item_id = i.item_id' : ''

      <<~SQL
        WITH matched_products AS (
          SELECT i.product_id
          FROM catalog_items i
          #{join_sql}
          WHERE #{where_sql}
          GROUP BY i.product_id
          ORDER BY MAX(i.sellable) DESC, MIN(i.price_amount) IS NULL ASC, MIN(i.price_amount) ASC,
                   MAX(i.in_stock) DESC, MIN(i.display_name) ASC
          LIMIT ?
        )
        SELECT i.*
        FROM matched_products
        INNER JOIN catalog_items i ON i.product_id = matched_products.product_id
        ORDER BY i.sellable DESC, i.price_amount IS NULL ASC, i.price_amount ASC,
                 i.in_stock DESC, i.display_name ASC
      SQL
    end

    def candidate_for(db, row, parsed, root, root_category_ids)
      constraints = parsed.fetch('constraints')
      evidence = []
      match_kind = 'exact'

      constraints.each do |constraint|
        match = match_constraint(db, row, constraint)
        return nil unless match

        evidence.concat(match.fetch('evidence'))
        match_kind = 'compatible' if match.fetch('kind') == 'compatible'
      end

      item_category_ids = item_category_ids(db, row.fetch('item_id'))
      relevance = relevance_for(db, row, parsed.fetch('terms'), root, root_category_ids, item_category_ids, evidence)
      candidate = {
        'item_id' => row.fetch('item_id'),
        'product_id' => row.fetch('product_id'),
        'variant_id' => row['variant_id'],
        'display_name' => row.fetch('display_name'),
        'category_paths' => category_paths_for(db, item_category_ids),
        'price' => price_payload_for(db, row),
        'stock' => {
          'available' => row.fetch('sellable').to_i.positive?,
          'in_stock' => row.fetch('in_stock').to_i.positive?,
          'sellable' => row.fetch('sellable').to_i.positive?,
          'quantity' => row['stock_quantity']
        },
        'confidence' => confidence_for(evidence),
        'match_kind' => match_kind,
        'match_reasons' => reasons_for(evidence, constraints),
        'evidence' => evidence,
        'relevance_score' => relevance.fetch('score'),
        'relevance_signals' => relevance.fetch('signals')
      }
      image = image_payload_for(db, row.fetch('item_id'))
      candidate['image'] = image if image
      candidate['link'] = link_for(row) if row['product_url'].to_s != ''
      candidate
    end

    def grouped_candidates(db, item_candidates)
      item_candidates.group_by { |candidate| candidate.fetch('product_id') }.values.map do |matches|
        grouped_candidate(db, matches)
      end
    end

    def grouped_candidate(db, matches)
      best = matches.first
      group = db.get_first_row('SELECT * FROM catalog_groups WHERE product_id = ?', [best.fetch('product_id')]) || {}
      visible_variants = matches.first(5).map { |match| matching_variant_payload(db, match) }
      candidate = best.merge(
        'display_name' => group['display_name'] || best.fetch('display_name'),
        'category_paths' => matches.flat_map { |match| match.fetch('category_paths') }.uniq,
        'matching_variant_count' => matches.length,
        'matching_variants' => visible_variants,
        'matching_variants_omitted' => matches.length - visible_variants.length,
        'price' => grouped_price_payload(matches),
        'stock' => grouped_stock_payload(matches)
      )
      candidate.delete('matching_variants_omitted') if candidate['matching_variants_omitted'].zero?
      candidate['link'] ||= link_for(group) if group['product_url'].to_s != ''
      configuration = configuration_for(db, best.fetch('product_id'))
      candidate['configuration'] = configuration if configuration
      candidate
    end

    def matching_variant_payload(db, candidate)
      {
        'variant_id' => candidate['variant_id'],
        'display_name' => candidate.fetch('display_name'),
        'options' => variant_options_for(db, candidate.fetch('item_id')),
        'price' => candidate.fetch('price'),
        'stock' => candidate.fetch('stock'),
        'link' => candidate['link'],
        'match_kind' => candidate.fetch('match_kind'),
        'evidence' => candidate.fetch('evidence')
      }.compact
    end

    def variant_options_for(db, item_id)
      db.execute('SELECT key, value FROM catalog_facets WHERE item_id = ? ORDER BY key ASC, value ASC', [item_id]).map do |row|
        { 'name' => row.fetch('key'), 'value' => row.fetch('value') }
      end
    end

    def grouped_price_payload(matches)
      prices = matches.map { |match| match.fetch('price') }
      custom_prices = prices.select { |price| price['final_total_known'] == false }
      return grouped_custom_price_payload(custom_prices) if custom_prices.any?

      amounts = prices.filter_map { |price| price['amount'] }.uniq.sort
      return prices.first if amounts.length <= 1

      currencies = prices.filter_map { |price| price['currency'] }.uniq
      payload = {
        'amount' => nil,
        'min_amount' => amounts.first,
        'max_amount' => amounts.last,
        'final_total_known' => true,
        'pricing_model' => 'range'
      }
      payload['currency'] = currencies.first if currencies.one?
      payload
    end

    def grouped_custom_price_payload(prices)
      amounts = prices.filter_map { |price| price['reference_amount'] }.uniq.sort
      currencies = prices.filter_map { |price| price['currency'] }.uniq
      payload = {
        'amount' => nil,
        'final_total_known' => false,
        'pricing_model' => amounts.length > 1 ? 'custom_options_range' : 'custom_options'
      }
      payload['reference_amount'] = amounts.first if amounts.one?
      if amounts.length > 1
        payload['min_reference_amount'] = amounts.first
        payload['max_reference_amount'] = amounts.last
      end
      payload['currency'] = currencies.first if currencies.one?
      payload
    end

    def grouped_stock_payload(matches)
      stocks = matches.map { |match| match.fetch('stock') }
      payload = {
        'available' => stocks.any? { |stock| stock['available'] },
        'in_stock' => stocks.any? { |stock| stock['in_stock'] },
        'sellable' => stocks.any? { |stock| stock['sellable'] },
        'matching_in_stock_count' => stocks.count { |stock| stock['in_stock'] },
        'matching_sellable_count' => stocks.count { |stock| stock['sellable'] }
      }
      payload['quantity'] = stocks.first['quantity'] if stocks.one?
      payload
    end

    def configuration_for(db, product_id)
      product_json = db.get_first_value('SELECT raw_json FROM raw_products WHERE id = ?', [product_id])
      return if product_json.to_s.empty?

      product = JSON.parse(product_json)
      option_set_id = product['productOptionSetId']
      return if option_set_id.to_s.empty?

      option_set_json = db.get_first_value('SELECT raw_json FROM raw_product_option_sets WHERE id = ?', [option_set_id])
      return if option_set_json.to_s.empty?

      options = configuration_options(JSON.parse(option_set_json))
      return if options.empty?

      { 'customizable' => true, 'options' => options }
    rescue JSON::ParserError
      nil
    end

    def configuration_options(option_set)
      options = Array(option_set['options']).sort_by { |option| option['order'].to_f }
      explicit_units = options.filter_map do |option|
        configuration_dimension_unit(option['name']) if dimension_option_axis(option['name'])
      end.uniq
      inherited_unit = explicit_units.first if explicit_units.one?
      options.filter_map do |option|
        axis = dimension_option_axis(option['name'])
        if option['type'].to_s.upcase == 'TEXT' && axis
          configuration_dimension_option(option, axis, inherited_unit)
        elsif option['type'].to_s.upcase == 'CHOICE'
          configuration_choice_option(option)
        end
      end
    end

    def configuration_dimension_option(option, axis, inherited_unit)
      unit = configuration_dimension_unit(option['name']) || inherited_unit || 'cm'
      {
        'name' => option.fetch('name'),
        'type' => 'dimension',
        'required' => option['isOptional'] != true,
        'axis' => axis,
        'unit' => 'cm',
        'min' => normalize_configuration_dimension(option.dig('textSettings', 'min'), unit),
        'max' => normalize_configuration_dimension(option.dig('textSettings', 'max'), unit)
      }.compact
    end

    def configuration_choice_option(option)
      values = Array(option.dig('selectSettings', 'values')).sort_by { |value| value['order'].to_f }.filter_map do |value|
        text = value['value'].to_s.strip
        text unless text.empty?
      end
      return if values.empty?

      { 'name' => option.fetch('name'), 'type' => 'choice', 'required' => option['isOptional'] != true, 'values' => values }
    end

    def dimension_option_axis(name)
      folded = Text.fold(name)
      return 'width' if folded.match?(/\b(en|width|genislik)\b/)
      return 'height' if folded.match?(/\b(boy|height|yukseklik)\b/)

      nil
    end

    def configuration_dimension_unit(name)
      folded = Text.fold(name)
      return 'mm' if folded.match?(/\bmm\b/)
      return 'cm' if folded.match?(/\bcm\b/)
      return 'm' if folded.match?(/\b(metre|meter)\b/) || name.to_s.match?(/\(\s*m\s*\)/i)

      nil
    end

    def normalize_configuration_dimension(value, unit)
      return if value.nil?

      numeric = value.to_f
      case unit
      when 'mm' then numeric / 10.0
      when 'm' then numeric * 100.0
      else numeric
      end
    end

    def image_payload_for(db, item_id)
      return unless table_exists?(db, 'catalog_item_images')

      row = db.get_first_row(<<~SQL, [item_id])
        SELECT COUNT(*) AS image_count, MIN(image_scope) AS image_scope
        FROM catalog_item_images
        WHERE item_id = ?
      SQL
      count = row&.fetch('image_count', 0).to_i
      return if count.zero?

      { 'available' => true, 'count' => count, 'scope' => row.fetch('image_scope') }
    end

    def table_exists?(db, table_name)
      query_cache[[:table_exists, table_name]] ||= db.get_first_value(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
        [table_name]
      ) == 1
    end

    def link_for(row)
      {
        'url' => row['product_url'],
        'source' => row['product_url_source'],
        'slug' => row['product_slug'],
        'storefront_domain' => row['storefront_domain']
      }.compact
    end

    def match_constraint(db, row, constraint)
      item_id = row.fetch('item_id')
      case constraint.fetch('type')
      when 'dimension_pair' then dimension_match(db, item_id, constraint)
      when 'dimension_axis' then dimension_axis_match(db, item_id, constraint)
      when 'weight', 'volume' then numeric_match(db, item_id, constraint)
      when 'facet' then value_match(db, row, constraint)
      else
        nil
      end
    end

    def dimension_match(db, item_id, constraint)
      values = constraint.fetch('values')
      facts = facts_for(db, item_id).select do |fact|
        %w[dimension_exact dimension_max dimension_range dimension_axis_range custom_size_supported].include?(fact.fetch('type'))
      end

      exact = facts.find { |fact| fact.fetch('type') == 'dimension_exact' && same_pair?(values, fact_values(fact)) }
      return match('exact', exact) if exact

      axis_facts = facts.select { |fact| fact.fetch('type') == 'dimension_axis_range' }
      if axis_facts.any?
        width = axis_facts.find { |fact| fact.fetch('key') == 'width' }
        height = axis_facts.find { |fact| fact.fetch('key') == 'height' }
        direct = width && height && dimension_axis_contains?(width, values[0]) && dimension_axis_contains?(height, values[1])
        rotated = width && height && dimension_axis_contains?(width, values[1]) && dimension_axis_contains?(height, values[0])
        maximum = compatible_dimension_max_fact(facts, values)
        return match_with_facts('compatible', [maximum, width, height]) if direct || rotated

        return nil
      end

      max = compatible_dimension_max_fact(facts, values)
      return match('compatible', max) if max

      range = facts.find { |fact| fact.fetch('type') == 'dimension_range' && values_fit_range?(values, fact_values(fact)) }
      return match('compatible', range) if range

      bounded = facts.any? { |fact| %w[dimension_exact dimension_max dimension_range].include?(fact.fetch('type')) }
      return nil if bounded

      custom = facts.find { |fact| fact.fetch('type') == 'custom_size_supported' }
      return match('compatible', custom) if custom

      nil
    end

    def dimension_axis_match(db, item_id, constraint)
      fact = facts_for(db, item_id).find do |row|
        row.fetch('type') == 'dimension_axis_range' && row.fetch('key') == constraint.fetch('key') &&
          dimension_axis_contains?(row, constraint.fetch('value'))
      end
      match('compatible', fact)
    end

    def dimension_axis_contains?(fact, requested_value)
      minimum = fact['numeric_value']
      maximum = fact['numeric_value_2']
      return false if minimum && requested_value.to_f < minimum.to_f
      return false if maximum && requested_value.to_f > maximum.to_f

      true
    end

    def numeric_match(db, item_id, constraint)
      fact = facts_for(db, item_id).find do |row|
        row.fetch('type') == constraint.fetch('type') &&
          row['unit'].to_s == constraint.fetch('unit').to_s &&
          row['numeric_value'].to_f == constraint.fetch('value').to_f
      end
      match('exact', fact) if fact
    end

    def value_match(db, row, constraint)
      folded = Text.fold(constraint.fetch('value'))
      typed_facts = facts_for(db, row.fetch('item_id')).select { |fact| fact.fetch('type') == constraint.fetch('type') }
      exact_facts, configurable_facts = typed_facts.partition { |fact| fact.fetch('source') != 'product_option_set' }
      fact = exact_facts.find do |typed_fact|
        typed_fact['value_folded'].to_s == folded
      end
      fact ||= exact_facts.find { |typed_fact| text_contains_value?(typed_fact['value_text'], folded) }
      return match('exact', fact) if fact

      title_match = title_facet_match(row, constraint, folded)
      return title_match if title_match

      configurable = configurable_facts.find { |typed_fact| typed_fact['value_folded'].to_s == folded }
      match('compatible', configurable)
    end

    def title_facet_match(row, constraint, folded)
      return nil unless text_contains_value?(row.fetch('display_name'), folded)

      match(
        'exact',
        {
          'source' => 'display_name',
          'type' => 'facet',
          'key' => constraint['key'],
          'value_text' => constraint.fetch('value'),
          'value_folded' => folded,
          'confidence' => 'medium',
          'raw' => row.fetch('display_name')
        }
      )
    end

    def text_contains_value?(text, folded_value)
      tokens = Text.tokens(text)
      return true if tokens.include?(folded_value)

      folded_text = " #{Text.fold(text)} "
      folded_text.include?(" #{folded_value} ")
    end

    def match(kind, fact)
      return nil unless fact

      { 'kind' => kind, 'evidence' => [evidence_for(fact, kind)] }
    end

    def match_with_facts(kind, facts)
      facts = Array(facts).compact
      return if facts.empty?

      { 'kind' => kind, 'evidence' => facts.map { |fact| evidence_for(fact, kind) } }
    end

    def evidence_for(fact, kind)
      {
        'source' => fact.fetch('source'),
        'fact' => fact.fetch('type'),
        'key' => fact['key'],
        'value' => fact['value_text'],
        'unit' => fact['unit'],
        'confidence' => fact.fetch('confidence'),
        'raw' => fact['raw'],
        'match_kind' => kind
      }
    end

    def facts_for(db, item_id)
      cache_fetch(:facts, item_id) do
        db.execute('SELECT * FROM catalog_facts WHERE item_id = ? ORDER BY confidence ASC, type ASC', [item_id])
      end
    end

    def fact_values(fact)
      [fact['numeric_value'], fact['numeric_value_2']].map(&:to_f)
    end

    def compatible_dimension_max_fact(facts, requested_values)
      facts.select { |fact| fact.fetch('type') == 'dimension_max' && pair_fits?(requested_values, fact_values(fact)) }
           .min_by { |fact| [dimension_area(fact_values(fact)), confidence_rank(fact.fetch('confidence'))] }
    end

    def dimension_area(values)
      values[0].to_f * values[1].to_f
    end

    def confidence_rank(confidence)
      { 'high' => 0, 'medium' => 1 }.fetch(confidence.to_s, 2)
    end

    def same_pair?(left, right)
      (left[0] == right[0] && left[1] == right[1]) || (left[0] == right[1] && left[1] == right[0])
    end

    def pair_fits?(requested, maximum)
      (requested[0] <= maximum[0] && requested[1] <= maximum[1]) ||
        (requested[0] <= maximum[1] && requested[1] <= maximum[0])
    end

    def values_fit_range?(requested, range_values)
      min, max = range_values.minmax
      requested.all? { |value| value.between?(min, max) }
    end

    def reasons_for(evidence, constraints)
      return ['matched search terms'] if constraints.empty?

      evidence.map do |row|
        case row.fetch('fact')
        when 'dimension_exact' then 'requested dimensions exactly match catalog dimensions'
        when 'dimension_max' then 'requested dimensions fit product max dimensions'
        when 'dimension_range' then 'requested dimensions fit catalog range'
        when 'dimension_axis_range' then "requested #{row.fetch('key')} fits configurable range"
        else "matched #{row.fetch('fact')}"
        end
      end.uniq
    end

    def confidence_for(evidence)
      return 'medium' if evidence.empty?
      return 'high' if evidence.all? { |row| row.fetch('confidence') == 'high' }

      'medium'
    end

    def relevance_for(db, row, terms, root, root_category_ids, item_category_ids, evidence)
      signals = []
      evidence.each do |evidence_row|
        add_relevance_signal(signals, evidence_signal_for(evidence_row))
      end

      category_matches = category_matching_terms(db, item_category_ids, terms)
      add_relevance_signal(signals, 'kind' => 'category_term_match', 'terms' => category_matches, 'score' => category_matches.length * 14)

      if fts_score_present?(row)
        add_relevance_signal(signals, fts_rank_signal_for(row))
      end
      add_relevance_signal(signals, display_name_prefix_signal_for(row, terms))

      if root && item_in_category_scope?(item_category_ids, root_category_ids)
        add_relevance_signal(signals, 'kind' => 'matched_category_scope', 'category_id' => root.fetch('id'), 'score' => 8)
      end

      { 'score' => signals.sum { |signal| signal.fetch('score') }, 'signals' => signals }
    end

    def evidence_signal_for(evidence_row)
      source = evidence_row.fetch('source')
      fact = evidence_row.fetch('fact')
      compatible = evidence_row.fetch('match_kind') == 'compatible'
      structured = STRUCTURED_EVIDENCE_SOURCES.include?(source)
      score = if compatible
                structured ? 35 : 20
              elsif structured
                30
              elsif source == 'display_name'
                14
              elsif source == 'text'
                8
              else
                10
              end

      {
        'kind' => structured ? 'structured_evidence_match' : 'fallback_evidence_match',
        'source' => source,
        'fact' => fact,
        'score' => score
      }
    end

    def fts_rank_signal_for(row)
      raw_score = -row['fts_score'].to_f
      score = [[raw_score * 2.0, 20].min, 1].max.round(3)
      { 'kind' => 'fts_bm25_match', 'raw_score' => raw_score.round(6), 'score' => score }
    end

    def fts_score_present?(row)
      row.key?('fts_score') && !row['fts_score'].nil?
    end

    def display_name_prefix_signal_for(row, terms)
      phrase = terms.join(' ')
      return { 'kind' => 'display_name_prefix_match', 'score' => 0 } if phrase.empty?

      folded_name = Text.fold(row.fetch('display_name'))
      return { 'kind' => 'display_name_prefix_match', 'phrase' => phrase, 'score' => 6 } if folded_name.start_with?(phrase)

      { 'kind' => 'display_name_prefix_match', 'score' => 0 }
    end

    def add_relevance_signal(signals, signal)
      return if signal.fetch('score').to_i <= 0

      signals << signal
    end

    def candidate_sort_key(candidate, terms)
      [
        -candidate.fetch('relevance_score').to_f,
        visible_term_miss_count(candidate.fetch('display_name'), terms),
        candidate.fetch('match_kind') == 'exact' ? 0 : 1,
        candidate.dig('stock', 'sellable') ? 0 : 1,
        candidate.dig('price', 'amount').nil? ? 1 : 0,
        candidate.dig('price', 'amount') || Float::INFINITY,
        candidate.dig('stock', 'in_stock') ? 0 : 1,
        candidate.fetch('display_name')
      ]
    end

    def visible_term_miss_count(display_name, terms)
      visible_tokens = Text.tokens(display_name)
      terms.count { |term| visible_tokens.none? { |visible_token| category_token_match?(term, visible_token) } }
    end

    def category_matching_terms(db, item_category_ids, terms)
      tokens = item_category_tokens(db, item_category_ids)
      terms.select { |term| tokens.any? { |token| category_token_match?(term, token) } }.uniq
    end

    def category_scope_terms_for(db, parsed)
      constraint_tokens = parsed.fetch('constraints').flat_map do |constraint|
        Text.tokens([constraint['raw'], constraint['value']].compact.join(' '))
      end
      terms = parsed.fetch('terms').reject do |term|
        constraint_tokens.any? { |token| category_token_match?(term, token) }
      end
      category_terms = terms.select { |term| category_scope_term?(db, term) }

      category_terms.length * 2 > terms.length ? category_terms : []
    end

    def price_payload_for(db, row)
      if custom_option_pricing_candidate?(db, row.fetch('item_id'))
        return {
          'amount' => nil,
          'currency' => row['currency'],
          'reference_amount' => row['price_amount'],
          'compare_at_reference_amount' => row['compare_at_price_amount'],
          'final_total_known' => false,
          'pricing_model' => 'custom_options'
        }
      end

      {
        'amount' => row['price_amount'],
        'currency' => row['currency'],
        'compare_at_amount' => row['compare_at_price_amount'],
        'final_total_known' => !row['price_amount'].nil?,
        'pricing_model' => 'fixed'
      }.compact
    end

    def custom_option_pricing_candidate?(db, item_id)
      facts_for(db, item_id).any? do |fact|
        fact.fetch('source') == 'product_option_set' &&
          %w[custom_size_supported dimension_max].include?(fact.fetch('type'))
      end
    end

    def item_category_tokens(db, item_category_ids)
      item_category_ids.flat_map { |category_id| category_path_tokens(db, category_id) }.uniq
    end

    def item_in_category_scope?(item_category_ids, root_category_ids)
      (item_category_ids & root_category_ids).any?
    end

    def item_category_ids(db, item_id)
      cache_fetch(:item_category_ids, item_id) do
        db.execute('SELECT category_id FROM catalog_item_categories WHERE item_id = ?', [item_id]).map { |row| row.fetch('category_id') }
      end
    end

    def category_paths_for(db, item_category_ids)
      item_category_ids.map do |category_id|
        names = category_path_names(db, category_id)
        next if names.empty?

        names.join(' > ')
      end.compact.uniq
    end

    def facet_vocabulary(db)
      cache_fetch(:query, :facet_vocabulary) do
        rows = db.execute('SELECT key, value FROM catalog_facets GROUP BY key, value').dup
        rows.concat(
          db.execute(
            "SELECT key, value_text AS value FROM catalog_facts WHERE source = 'product_option_set' AND type = 'facet' GROUP BY key, value_text"
          )
        )
        rows.group_by { |row| row.fetch('key') }.transform_values { |values| values.map { |row| row.fetch('value') }.uniq }
      end
    end

    def matched_root(db, terms)
      return nil if terms.empty?

      candidates = category_rows(db).select do |row|
        next false if group_count_for_categories(db, category_subtree_ids(db, row.fetch('id'))).zero?

        folded_words = category_path_tokens(db, row.fetch('id'))
        terms.all? { |term| folded_words.any? { |word| category_token_match?(term, word) } }
      end
      return nil if candidates.empty?
      return candidates.first if candidates.length == 1
      exact = exact_category_name_match(db, candidates, terms)
      return exact if exact

      substantial = substantial_category_match(db, candidates)
      return substantial if substantial

      common_ancestor_for(db, candidates) || candidates.max_by { |row| category_subtree_ids(db, row.fetch('id')).length }
    end

    def exact_category_name_match(db, categories, terms)
      return nil if terms.length < 2

      categories.map do |row|
        name_tokens = Text.tokens(row.fetch('name'))
        matched_terms = terms.count { |term| name_tokens.any? { |word| category_token_match?(term, word) } }
        next unless matched_terms == terms.length

        extra_tokens = name_tokens.count { |word| terms.none? { |term| category_token_match?(term, word) } }
        [row, extra_tokens, category_subtree_ids(db, row.fetch('id')).length]
      end.compact
        .min_by { |_row, extra_tokens, subtree_size| [extra_tokens, subtree_size] }
        &.first
    end

    def substantial_category_match(db, categories)
      categories.map do |row|
        [row, group_count_for_categories(db, category_subtree_ids(db, row.fetch('id')))]
      end.select { |_row, count| count >= 10 }
        .max_by { |_row, count| count }
        &.first
    end

    def search_terms_for(db, root, terms)
      return terms unless root

      root_words = category_path_tokens(db, root.fetch('id'))
      terms.reject { |term| root_words.any? { |word| category_token_match?(term, word) } }
    end

    def category_token_match?(left, right)
      left_variants = category_token_variants(left)
      right_variants = category_token_variants(right)
      return true if (left_variants & right_variants).any?
      return true if inflected_category_token_match?(left_variants, right_variants)
      return true if shared_stem_category_token_match?(left_variants, right_variants)

      left_variants.any? do |left_token|
        right_variants.any? { |right_token| similar_category_token?(left_token, right_token) }
      end
    end

    def inflected_category_token_match?(left_variants, right_variants)
      left_variants.any? do |left_token|
        right_variants.any? do |right_token|
          shorter, longer = [left_token, right_token].sort_by(&:length)
          max_suffix_length = shorter.length == 4 ? 2 : 3
          shorter.length >= 4 && longer.start_with?(shorter) && longer.length - shorter.length <= max_suffix_length
        end
      end
    end

    def shared_stem_category_token_match?(left_variants, right_variants)
      left_variants.any? do |left_token|
        right_variants.any? do |right_token|
          minimum_length = [left_token.length, right_token.length].min
          common_prefix_length = left_token.chars.zip(right_token.chars).take_while { |left_char, right_char| left_char == right_char }.length

          close_short_stem = common_prefix_length >= 4 && levenshtein_distance(left_token, right_token) <= 3
          minimum_length >= 6 && (common_prefix_length >= 5 || close_short_stem) && common_prefix_length * 3 >= minimum_length * 2
        end
      end
    end

    def catalog_scope_term?(db, term)
      category_scope_term?(db, term) || selective_item_scope_term?(db, term)
    end

    def category_scope_term?(db, term)
      category_rows(db).any? do |row|
        category_path_tokens(db, row.fetch('id')).any? { |word| category_token_match?(term, word) }
      end
    end

    def selective_item_scope_term?(db, term)
      folded_term = Text.fold(term)
      cache_fetch(:selective_item_scope_terms, folded_term) do
        total = cache_fetch(:query, :catalog_group_count) do
          db.get_first_value('SELECT COUNT(DISTINCT group_id) FROM catalog_items').to_i
        end
        next false if total.zero?

        matches = db.get_first_value(
          'SELECT COUNT(DISTINCT group_id) FROM catalog_items WHERE search_text_folded LIKE ?',
          ["%#{folded_term}%"]
        ).to_i
        matches.positive? && matches <= [(total * 0.2).ceil, 5].max
      end
    end

    def category_token_variants(value)
      token = Text.fold(value)
      token.empty? ? [] : [token]
    end

    def similar_category_token?(left, right)
      min_length = [left.length, right.length].min
      return false if min_length < 6

      distance = levenshtein_distance(left, right)
      distance <= (min_length >= 7 ? 2 : 1)
    end

    def levenshtein_distance(left, right)
      previous = (0..right.length).to_a
      left.chars.each_with_index do |left_char, left_index|
        current = [left_index + 1]
        right.chars.each_with_index do |right_char, right_index|
          cost = left_char == right_char ? 0 : 1
          current << [
            current[right_index] + 1,
            previous[right_index + 1] + 1,
            previous[right_index] + cost
          ].min
        end
        previous = current
      end
      previous.last
    end

    def common_ancestor_for(db, categories)
      paths = categories.map { |row| category_path_ids(db, row.fetch('id')) }
      ancestor_id = paths.first.find { |candidate_id| paths.all? { |path| path.include?(candidate_id) } }
      category_rows_by_id(db)[ancestor_id] if ancestor_id
    end

    def category_path_ids(db, category_id)
      cache_fetch(:category_path_ids, category_id) do
        rows_by_id = category_rows_by_id(db)
        path = []
        current = rows_by_id[category_id]
        while current
          path << current.fetch('id')
          current = rows_by_id[current['parent_id']]
        end
        path
      end
    end

    def category_path_tokens(db, category_id)
      cache_fetch(:category_path_tokens, category_id) do
        category_path_ids(db, category_id).flat_map { |id| Text.tokens(category_rows_by_id(db).fetch(id).fetch('name')) }
      end
    end

    def category_path_names(db, category_id)
      cache_fetch(:category_path_names, category_id) do
        category_path_ids(db, category_id).reverse.map { |id| category_rows_by_id(db).fetch(id).fetch('name') }
      end
    end

    def type_buckets(db, category_id)
      children = child_categories(db, category_id)
      children.filter_map do |row|
        ids = category_subtree_ids(db, row.fetch('id'))
        count = group_count_for_categories(db, ids)
        next unless count.positive?

        bucket = {
          'category_id' => row.fetch('id'),
          'label' => row.fetch('name'),
          'group_count' => count,
          'children' => child_type_buckets(db, row.fetch('id'))
        }
        hidden_count = hidden_children_count(db, row.fetch('id'), bucket.fetch('children').length)
        bucket['hidden_children_count'] = hidden_count if hidden_count.positive?
        bucket
      end.sort_by { |row| [-row.fetch('group_count'), row.fetch('label')] }
    end

    def candidate_bucket_id(db, product_id, buckets)
      group_id = db.get_first_value('SELECT group_id FROM catalog_groups WHERE product_id = ?', [product_id])
      category_ids = db.execute('SELECT category_id FROM catalog_group_categories WHERE group_id = ?', [group_id]).map do |row|
        row.fetch('category_id')
      end
      buckets.find do |bucket|
        (category_ids & category_subtree_ids(db, bucket.fetch('category_id'))).any?
      end&.fetch('category_id')
    end

    def child_type_buckets(db, category_id)
      children = child_categories(db, category_id)
      children.filter_map do |row|
        ids = category_subtree_ids(db, row.fetch('id'))
        count = group_count_for_categories(db, ids)
        next unless count.positive?

        { 'category_id' => row.fetch('id'), 'label' => row.fetch('name'), 'group_count' => count }
      end.sort_by { |row| [-row.fetch('group_count'), row.fetch('label')] }
         .first(CHILD_BUCKET_LIMIT)
    end

    def hidden_children_count(db, category_id, visible_count)
      total = child_categories(db, category_id).count do |row|
        group_count_for_categories(db, category_subtree_ids(db, row.fetch('id'))).positive?
      end
      hidden_count = total - visible_count
      [hidden_count, 0].max
    end

    def category_subtree_ids(db, category_id)
      cache_fetch(:category_subtree_ids, category_id) do
        descendants = [category_id]
        cursor = 0
        while cursor < descendants.length
          descendants.concat(child_categories(db, descendants[cursor]).map { |row| row.fetch('id') })
          cursor += 1
        end
        descendants
      end
    end

    def group_count_for_categories(db, category_ids)
      return 0 if category_ids.empty?

      cache_fetch(:category_group_counts, category_ids.sort) do
        db.get_first_value(
          "SELECT COUNT(DISTINCT group_id) FROM catalog_group_categories WHERE category_id IN (#{placeholders(category_ids)})",
          category_ids
        ).to_i
      end
    end

    def category_rows(db)
      cache_fetch(:query, :category_rows) do
        db.execute('SELECT id, parent_id, name FROM raw_categories')
      end
    end

    def category_rows_by_id(db)
      cache_fetch(:query, :category_rows_by_id) do
        category_rows(db).index_by { |row| row.fetch('id') }
      end
    end

    def child_categories(db, category_id)
      cache_fetch(:child_categories, category_id) do
        category_rows(db).select { |row| row['parent_id'] == category_id }.sort_by { |row| row.fetch('name') }
      end
    end

    def cache_fetch(namespace, key)
      namespace_cache = query_cache[namespace] ||= {}
      return namespace_cache[key] if namespace_cache.key?(key)

      namespace_cache[key] = yield
    end

    def query_cache
      @query_cache ||= {}
    end

    def placeholders(values)
      Array.new(values.length, '?').join(',')
    end

    def with_db
      db = SQLite3::Database.new(sqlite_path.to_s)
      db.results_as_hash = true
      @query_cache = {}
      yield db
    ensure
      @query_cache = nil
      db&.close
    end
  end
end
