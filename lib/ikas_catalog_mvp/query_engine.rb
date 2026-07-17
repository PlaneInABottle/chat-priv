# frozen_string_literal: true

require 'sqlite3'

module IkasCatalogMvp
  class QueryEngine
    DEFAULT_LIMIT = 8
    CHILD_BUCKET_LIMIT = 5
    SEARCH_BACKEND = 'fts5'.freeze
    STRUCTURED_EVIDENCE_SOURCES = %w[facet product_attribute product_option_set product price stock].freeze

    def initialize(sqlite_path:)
      @sqlite_path = sqlite_path
    end

    def query(text, limit: DEFAULT_LIMIT, context_texts: [])
      with_db do |db|
        plan = query_plan_for(db, text, context_texts)
        return needs_scope_payload(text, plan.fetch('parsed')) if plan.fetch('needs_scope')

        parsed = plan.fetch('parsed')
        return unsupported_payload(plan.fetch('query'), parsed) if parsed.fetch('unsupported_constraints').any?

        root = matched_root(db, category_scope_terms_for(db, parsed))
        buckets = root ? type_buckets(db, root.fetch('id')) : []
        if clarification_needed?(parsed, buckets)
          return clarify_payload(text, parsed, root, buckets)
        end

        root_category_ids = root ? category_subtree_ids(db, root.fetch('id')) : []
        candidates = candidates_for(db, parsed, root, root_category_ids, limit)

        result_payload(plan.fetch('query'), parsed, root, candidates)
      end
    end

    def context_required_for?(text)
      with_db do |db|
        parsed = query_parser(db).parse(text)
        scope_required?(db, parsed)
      end
    end

    private

    attr_reader :sqlite_path

    def query_parser(db)
      QueryParser.new(facet_vocabulary: facet_vocabulary(db))
    end

    def query_plan_for(db, text, context_texts)
      parsed = query_parser(db).parse(text)
      return { 'query' => text, 'parsed' => parsed, 'needs_scope' => false } unless scope_required?(db, parsed)

      context_terms = latest_context_scope_terms(db, context_texts)
      return { 'query' => text, 'parsed' => parsed, 'needs_scope' => true } if context_terms.empty?

      query = scoped_constraint_query(context_terms, parsed)
      { 'query' => query, 'parsed' => query_parser(db).parse(query), 'needs_scope' => false }
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

    def latest_context_scope_terms(db, context_texts)
      Array(context_texts).reverse_each do |context_text|
        terms = scope_terms_for(db, query_parser(db).parse(context_text), include_item_scope: false)
        terms = terms.select { |term| Text.fold(term).length >= 3 }
        return terms if terms.any?
      end
      []
    end

    def scope_terms_for(db, parsed, include_item_scope: true)
      parsed.fetch('terms').select { |term| catalog_scope_term?(db, term, include_item_scope: include_item_scope) }
    end

    def scoped_constraint_query(scope_terms, parsed)
      constraint_text = parsed.fetch('constraints').filter_map { |constraint| constraint['raw'] }.join(' ')
      [scope_terms.join(' '), constraint_text].reject { |value| value.to_s.empty? }.join(' ').split.join(' ')
    end

    def clarification_needed?(parsed, buckets)
      parsed.fetch('constraints').empty? && buckets.length > 1
    end

    def clarify_payload(text, parsed, root, buckets)
      {
        'result_type' => 'clarify_category',
        'query' => text,
        'parsed' => parsed,
        'matched_scope' => root,
        'buckets' => buckets.first(DEFAULT_LIMIT),
        'search_backend' => SEARCH_BACKEND,
        'next_action' => 'ask_customer_to_choose_category_or_type'
      }
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
      rows.filter_map { |row| candidate_for(db, row, parsed, root, root_category_ids) }
          .sort_by { |candidate| candidate_sort_key(candidate, parsed.fetch('terms')) }
          .first(limit)
    end

    def category_matching_rows(db, limit, category_ids:)
      sql = category_matching_rows_sql(category_ids)
      bindings = category_ids.dup
      bindings << [limit * 8, 50].max
      db.execute(sql, bindings)
    end

    def fts5_available?(db)
      db.get_first_value("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'catalog_items_fts'").to_s != ''
    end

    def fts5_matching_rows(db, fts5_terms, limit, category_ids:, operator: 'AND')
      bindings = [fts5_query_for(fts5_terms, operator: operator)]
      bindings.concat(category_ids)
      bindings << [limit * 8, 50].max
      db.execute(fts5_matching_rows_sql(category_ids), bindings)
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
        SELECT DISTINCT i.*, bm25(catalog_items_fts, 0.0, 10.0, 1.0) AS fts_score
        FROM catalog_items_fts
        INNER JOIN catalog_items i ON i.item_id = catalog_items_fts.item_id
        #{join_sql}
        WHERE #{clauses.join(' AND ')}
        ORDER BY fts_score ASC, i.sellable DESC, i.price_amount IS NULL ASC, i.price_amount ASC, i.in_stock DESC, i.display_name ASC
        LIMIT ?
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
        SELECT DISTINCT i.*
        FROM catalog_items i
        #{join_sql}
        WHERE #{where_sql}
        ORDER BY i.sellable DESC, i.price_amount IS NULL ASC, i.price_amount ASC, i.in_stock DESC, i.display_name ASC
        LIMIT ?
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
      candidate['link'] = link_for(row) if row['product_url'].to_s != ''
      candidate
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
      when 'weight', 'volume' then numeric_match(db, item_id, constraint)
      when 'facet' then value_match(db, row, constraint)
      else
        nil
      end
    end

    def dimension_match(db, item_id, constraint)
      values = constraint.fetch('values')
      facts = facts_for(db, item_id).select { |fact| %w[dimension_exact dimension_max dimension_range custom_size_supported].include?(fact.fetch('type')) }

      exact = facts.find { |fact| fact.fetch('type') == 'dimension_exact' && same_pair?(values, fact_values(fact)) }
      return match('exact', exact) if exact

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
      fact = typed_facts.find do |typed_fact|
        typed_fact['value_folded'].to_s == folded
      end
      fact ||= typed_facts.find { |typed_fact| text_contains_value?(typed_fact['value_text'], folded) }
      return match('exact', fact) if fact

      title_facet_match(row, constraint, folded) if typed_facts.empty?
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
        db.execute('SELECT key, value FROM catalog_facets GROUP BY key, value').group_by { |row| row.fetch('key') }
          .transform_values { |rows| rows.map { |row| row.fetch('value') } }
      end
    end

    def matched_root(db, terms)
      return nil if terms.empty?

      candidates = category_rows(db).select do |row|
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

    def catalog_scope_term?(db, term, include_item_scope: true)
      category_scope_term?(db, term) || (include_item_scope && selective_item_scope_term?(db, term))
    end

    def category_scope_term?(db, term)
      category_rows(db).any? do |row|
        category_path_tokens(db, row.fetch('id')).any? { |word| category_token_match?(term, word) }
      end
    end

    def selective_item_scope_term?(db, term)
      total = db.get_first_value('SELECT COUNT(DISTINCT group_id) FROM catalog_items').to_i
      return false if total.zero?

      matches = db.get_first_value(
        'SELECT COUNT(DISTINCT group_id) FROM catalog_items WHERE search_text_folded LIKE ?',
        ["%#{Text.fold(term)}%"]
      ).to_i
      matches.positive? && matches <= [(total * 0.2).ceil, 5].max
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
