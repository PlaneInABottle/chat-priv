# frozen_string_literal: true

class AiAgents::LlmToolResultPresenter
  SINGLE_QUERY_CANDIDATE_LIMIT = 8
  BATCH_QUERY_CANDIDATE_LIMIT = 4
  MATCHING_VARIANT_LIMIT = 3
  CATALOG_DEBUG_KEYS = %w[parsed search_backend catalog].freeze
  CANDIDATE_FIELDS = %w[
    item_id product_id display_name category_paths price stock evidence image link
    matching_variant_count matching_variants matching_variants_omitted configuration
  ].freeze
  STOCK_FIELDS = %w[in_stock sellable quantity matching_in_stock_count matching_sellable_count].freeze

  def initialize(tool_key:, result:)
    @tool_key = tool_key.to_s
    @result = result.to_h.deep_stringify_keys
  end

  def call
    return result unless tool_key == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL

    compact_catalog_result(result, candidate_limit: SINGLE_QUERY_CANDIDATE_LIMIT, batch: true)
  end

  private

  attr_reader :tool_key, :result

  def compact_catalog_result(payload, candidate_limit:, batch: false)
    compacted = payload.except(*CATALOG_DEBUG_KEYS)
    compacted['candidates'] = compact_candidates(compacted['candidates'], candidate_limit, compacted) if compacted.key?('candidates')
    if batch && compacted['queries'].is_a?(Array)
      compacted['queries'] = compacted['queries'].map do |query_result|
        compact_catalog_result(query_result.to_h.deep_stringify_keys, candidate_limit: BATCH_QUERY_CANDIDATE_LIMIT)
      end
    end
    compacted
  end

  def compact_candidates(candidates, limit, payload)
    candidates = Array(candidates)
    visible_candidates = candidates.first(limit).map { |candidate| compact_candidate(candidate) }
    omitted_count = candidates.length - visible_candidates.length
    payload['candidates_omitted'] = omitted_count if omitted_count.positive?
    visible_candidates
  end

  def compact_candidate(candidate)
    candidate = candidate.to_h.deep_stringify_keys.slice(*CANDIDATE_FIELDS)
    candidate['stock'] = candidate['stock'].to_h.slice(*STOCK_FIELDS) if candidate.key?('stock')
    compact_matching_variants(candidate)
    candidate
  end

  def compact_matching_variants(candidate)
    return unless candidate['matching_variants'].is_a?(Array)

    variants = candidate.fetch('matching_variants').first(MATCHING_VARIANT_LIMIT).map do |variant|
      variant = variant.to_h.deep_stringify_keys
      variant['stock'] = variant['stock'].to_h.slice(*STOCK_FIELDS) if variant.key?('stock')
      variant
    end
    candidate['matching_variants'] = variants
    total = candidate['matching_variant_count'].to_i
    omitted = total - variants.length
    omitted.positive? ? candidate['matching_variants_omitted'] = omitted : candidate.delete('matching_variants_omitted')
  end
end
