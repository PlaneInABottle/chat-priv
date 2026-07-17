# frozen_string_literal: true

class AiAgents::LlmToolResultPresenter
  SINGLE_QUERY_CANDIDATE_LIMIT = 8
  BATCH_QUERY_CANDIDATE_LIMIT = 4
  CATALOG_DEBUG_KEYS = %w[parsed search_backend catalog].freeze
  CANDIDATE_FIELDS = %w[display_name category_paths price stock evidence link].freeze
  STOCK_FIELDS = %w[sellable quantity].freeze

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
    candidate
  end
end
