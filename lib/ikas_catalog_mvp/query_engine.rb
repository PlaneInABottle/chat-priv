# frozen_string_literal: true

require 'sqlite3'

module IkasCatalogMvp
  class QueryEngine
    DEFAULT_LIMIT = 8

    def initialize(sqlite_path:)
      @sqlite_path = sqlite_path
    end

    def query(text, limit: DEFAULT_LIMIT, context_texts: [])
      with_db do |db|
        plan = query_plan_for(db, text, context_texts)
        return needs_scope_payload(text, plan.fetch('parsed')) if plan.fetch('needs_scope')

        parsed = plan.fetch('parsed')
        return unsupported_payload(plan.fetch('query'), parsed) if parsed.fetch('unsupported_constraints').any?

        root = matched_root(db, parsed.fetch('terms'))
        buckets = root ? type_buckets(db, root.fetch('id')) : []
        if clarification_needed?(parsed, buckets)
          return clarify_payload(text, parsed, root, buckets)
        end

        rows = matching_rows(db, parsed, root, limit)
        rows = matching_rows(db, parsed, nil, limit) if rows.empty? && root
        candidates = rows.filter_map { |row| candidate_for(db, row, parsed.fetch('constraints')) }
                         .sort_by { |candidate| candidate_sort_key(candidate, parsed.fetch('terms')) }
                         .first(limit)

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
        'next_action' => 'ask_customer_to_choose_category_or_type'
      }
    end

    def unsupported_payload(text, parsed)
      {
        'result_type' => 'unsupported',
        'query' => text,
        'parsed' => parsed,
        'candidates' => [],
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
        'warnings' => []
      }
    end

    def matching_rows(db, parsed, root, limit)
      terms = search_terms_for(db, root, parsed.fetch('terms'))
      category_ids = root ? category_subtree_ids(db, root.fetch('id')) : []
      sql = matching_rows_sql(terms, category_ids)
      bindings = terms.map { |term| "%#{term}%" }
      bindings.concat(category_ids)
      bindings << [limit * 8, 50].max
      db.execute(sql, bindings)
    end

    def matching_rows_sql(terms, category_ids)
      clauses = []
      clauses.concat(terms.map { 'i.search_text_folded LIKE ?' })
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

    def candidate_for(db, row, constraints)
      evidence = []
      match_kind = 'exact'

      constraints.each do |constraint|
        match = match_constraint(db, row.fetch('item_id'), constraint)
        return nil unless match

        evidence.concat(match.fetch('evidence'))
        match_kind = 'compatible' if match.fetch('kind') == 'compatible'
      end

      candidate = {
        'item_id' => row.fetch('item_id'),
        'product_id' => row.fetch('product_id'),
        'variant_id' => row['variant_id'],
        'display_name' => row.fetch('display_name'),
        'price' => { 'amount' => row['price_amount'], 'currency' => row['currency'] },
        'stock' => {
          'available' => row.fetch('sellable').to_i.positive?,
          'in_stock' => row.fetch('in_stock').to_i.positive?,
          'sellable' => row.fetch('sellable').to_i.positive?,
          'quantity' => row['stock_quantity']
        },
        'confidence' => confidence_for(evidence),
        'match_kind' => match_kind,
        'match_reasons' => reasons_for(evidence, constraints),
        'evidence' => evidence
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

    def match_constraint(db, item_id, constraint)
      case constraint.fetch('type')
      when 'dimension_pair' then dimension_match(db, item_id, constraint)
      when 'custom_size_requested' then fact_match(db, item_id, 'custom_size_supported')
      when 'stock' then fact_match(db, item_id, 'stock', numeric: 1)
      when 'price' then price_match(db, item_id, constraint)
      when 'weight', 'volume' then numeric_match(db, item_id, constraint)
      when 'organic' then fact_match(db, item_id, 'organic', numeric: 1)
      when 'size', 'color', 'facet' then value_match(db, item_id, constraint)
      else
        nil
      end
    end

    def dimension_match(db, item_id, constraint)
      values = constraint.fetch('values')
      facts = facts_for(db, item_id).select { |fact| %w[dimension_exact dimension_max dimension_range custom_size_supported].include?(fact.fetch('type')) }

      exact = facts.find { |fact| fact.fetch('type') == 'dimension_exact' && same_pair?(values, fact_values(fact)) }
      return match('exact', exact) if exact

      max = facts.find { |fact| fact.fetch('type') == 'dimension_max' && pair_fits?(values, fact_values(fact)) }
      return match('compatible', max) if max

      range = facts.find { |fact| fact.fetch('type') == 'dimension_range' && values_fit_range?(values, fact_values(fact)) }
      return match('compatible', range) if range

      bounded = facts.any? { |fact| %w[dimension_exact dimension_max dimension_range].include?(fact.fetch('type')) }
      return nil if bounded

      custom = facts.find { |fact| fact.fetch('type') == 'custom_size_supported' }
      return match('compatible', custom) if custom

      nil
    end

    def price_match(db, item_id, constraint)
      fact = facts_for(db, item_id).find { |row| row.fetch('type') == 'price' && row['numeric_value'].to_f <= constraint.fetch('value').to_f }
      match('exact', fact) if fact
    end

    def numeric_match(db, item_id, constraint)
      fact = facts_for(db, item_id).find do |row|
        row.fetch('type') == constraint.fetch('type') &&
          row['unit'].to_s == constraint.fetch('unit').to_s &&
          row['numeric_value'].to_f == constraint.fetch('value').to_f
      end
      match('exact', fact) if fact
    end

    def value_match(db, item_id, constraint)
      folded = Text.fold(constraint.fetch('value'))
      fact = facts_for(db, item_id).find do |row|
        row.fetch('type') == constraint.fetch('type') && row['value_folded'].to_s == folded
      end
      match('exact', fact) if fact
    end

    def fact_match(db, item_id, type, numeric: nil)
      fact = facts_for(db, item_id).find do |row|
        row.fetch('type') == type && (numeric.nil? || row['numeric_value'].to_i == numeric)
      end
      match(type == 'custom_size_supported' ? 'compatible' : 'exact', fact) if fact
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
      db.execute('SELECT * FROM catalog_facts WHERE item_id = ? ORDER BY confidence ASC, type ASC', [item_id])
    end

    def fact_values(fact)
      [fact['numeric_value'], fact['numeric_value_2']].map(&:to_f)
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
        when 'custom_size_supported' then 'catalog indicates custom size support'
        when 'organic' then 'catalog indicates organic or natural product'
        else "matched #{row.fetch('fact')}"
        end
      end.uniq
    end

    def confidence_for(evidence)
      return 'medium' if evidence.empty?
      return 'high' if evidence.all? { |row| row.fetch('confidence') == 'high' }

      'medium'
    end

    def candidate_sort_key(candidate, terms)
      [
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

    def facet_vocabulary(db)
      db.execute('SELECT key, value FROM catalog_facets GROUP BY key, value').group_by { |row| row.fetch('key') }
        .transform_values { |rows| rows.map { |row| row.fetch('value') } }
    end

    def matched_root(db, terms)
      return nil if terms.empty?

      candidates = db.execute('SELECT id, parent_id, name FROM raw_categories').select do |row|
        folded_words = category_path_tokens(db, row.fetch('id'))
        terms.all? { |term| folded_words.any? { |word| category_token_match?(term, word) } }
      end
      return nil if candidates.empty?
      return candidates.first if candidates.length == 1
      substantial = substantial_category_match(db, candidates)
      return substantial if substantial

      common_ancestor_for(db, candidates) || candidates.max_by { |row| category_subtree_ids(db, row.fetch('id')).length }
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

      left_variants.any? do |left_token|
        right_variants.any? { |right_token| similar_category_token?(left_token, right_token) }
      end
    end

    def catalog_scope_term?(db, term, include_item_scope: true)
      category_scope_term?(db, term) || (include_item_scope && selective_item_scope_term?(db, term))
    end

    def category_scope_term?(db, term)
      db.execute('SELECT id FROM raw_categories').any? do |row|
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
      return [] if token.empty?

      stemmed_category_tokens(token).flat_map { |candidate| softened_turkish_final_variants(candidate) }
                                   .uniq
    end

    def stemmed_category_tokens(token)
      candidates = [token, singular_category_token(token)]
      suffixes = %w[leri lari ler lar nden ndan den dan nin nun in un si su yi yu ye ya de da i u a e]
      suffixes.each do |suffix|
        next unless token.end_with?(suffix)

        stem = token.delete_suffix(suffix)
        candidates << singular_category_token(stem) if stem.length >= 3
      end
      candidates.reject(&:empty?).uniq
    end

    def softened_turkish_final_variants(token)
      variants = [token]
      final_map = { 'b' => 'p', 'd' => 't', 'g' => 'k' }
      replacement = final_map[token[-1]]
      variants << "#{token[0...-1]}#{replacement}" if replacement && token.length > 3
      variants
    end

    def singular_category_token(token)
      return token.delete_suffix('ler') if token.length > 5 && token.end_with?('ler')
      return token.delete_suffix('lar') if token.length > 5 && token.end_with?('lar')
      return token.delete_suffix('s') if token.length > 3 && token.end_with?('s') && !token.end_with?('ss')

      token
    end

    def similar_category_token?(left, right)
      min_length = [left.length, right.length].min
      return false if min_length < 7

      distance = levenshtein_distance(left, right)
      distance <= 2
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
      db.get_first_row('SELECT id, parent_id, name FROM raw_categories WHERE id = ?', [ancestor_id]) if ancestor_id
    end

    def category_path_ids(db, category_id)
      db.execute(
        <<~SQL,
          WITH RECURSIVE ancestors(id, parent_id) AS (
            SELECT id, parent_id FROM raw_categories WHERE id = ?
            UNION ALL
            SELECT c.id, c.parent_id FROM raw_categories c INNER JOIN ancestors a ON a.parent_id = c.id
          )
          SELECT id FROM ancestors
        SQL
        [category_id]
      ).map { |row| row.fetch('id') }
    end

    def category_path_tokens(db, category_id)
      db.execute(
        <<~SQL,
          WITH RECURSIVE ancestors(id, parent_id, name) AS (
            SELECT id, parent_id, name FROM raw_categories WHERE id = ?
            UNION ALL
            SELECT c.id, c.parent_id, c.name FROM raw_categories c INNER JOIN ancestors a ON a.parent_id = c.id
          )
          SELECT name FROM ancestors
        SQL
        [category_id]
      ).flat_map { |row| Text.tokens(row.fetch('name')) }
    end

    def type_buckets(db, category_id)
      children = db.execute('SELECT id, name FROM raw_categories WHERE parent_id = ? ORDER BY name ASC', [category_id])
      children.filter_map do |row|
        ids = category_subtree_ids(db, row.fetch('id'))
        count = group_count_for_categories(db, ids)
        next unless count.positive?

        { 'category_id' => row.fetch('id'), 'label' => row.fetch('name'), 'group_count' => count }
      end.sort_by { |row| [-row.fetch('group_count'), row.fetch('label')] }
    end

    def category_subtree_ids(db, category_id)
      db.execute(
        <<~SQL,
          WITH RECURSIVE subtree(id) AS (
            SELECT id FROM raw_categories WHERE id = ?
            UNION ALL
            SELECT c.id FROM raw_categories c INNER JOIN subtree ON c.parent_id = subtree.id
          )
          SELECT id FROM subtree
        SQL
        [category_id]
      ).map { |row| row.fetch('id') }
    end

    def group_count_for_categories(db, category_ids)
      return 0 if category_ids.empty?

      db.get_first_value(
        "SELECT COUNT(DISTINCT group_id) FROM catalog_group_categories WHERE category_id IN (#{placeholders(category_ids)})",
        category_ids
      ).to_i
    end

    def placeholders(values)
      Array.new(values.length, '?').join(',')
    end

    def with_db
      db = SQLite3::Database.new(sqlite_path.to_s)
      db.results_as_hash = true
      yield db
    ensure
      db&.close
    end
  end
end
