# frozen_string_literal: true

require Rails.root.join('lib/integrations/ikas/catalog')

class AiAgents::Tools::IkasCatalogSearchService
  MAX_BATCH_QUERIES = 3

  def self.normalize_queries(raw_queries, limit: MAX_BATCH_QUERIES)
    seen = {}

    Array(raw_queries).each_with_object([]) do |raw_query, queries|
      query = raw_query.to_s.strip
      next if query.blank?

      identity = Integrations::Ikas::Catalog::Text.fold(query).presence || query
      next if seen[identity]

      seen[identity] = true
      queries << query
      break queries if queries.length == limit
    end
  end

  def initialize(ai_agent:, account:, mode:, settings:, **_context)
    @ai_agent = ai_agent
    @account = account
    @mode = mode
    @settings = settings || {}
  end

  def call(args:)
    args ||= {}
    queries = normalized_queries(args)
    return invalid_query_payload if queries.empty?

    results = queries.map { |query| [query, search_catalog(query, args)] }
    return results.first.last if results.one?

    multi_search_payload(results)
  end

  private

  def normalized_queries(args)
    raw_queries = args.key?('queries') ? Array(args['queries']) : [args['query']]
    self.class.normalize_queries(raw_queries)
  end

  def search_catalog(query, args)
    Integrations::Ikas::CatalogSearchService.new(
      account: account,
      query_text: query,
      limit: args['limit'].presence || Integrations::Ikas::CatalogSearchService::DEFAULT_LIMIT
    ).call
  end

  def invalid_query_payload
    {
      status: 'error',
      error_code: 'invalid_query',
      error_message: 'Catalog query cannot be blank.',
      warnings: []
    }
  end

  def multi_search_payload(results)
    child_results = results.map { |query, result| child_result_payload(query, result) }
    warnings = child_results.flat_map { |result| Array(result[:warnings]) }.uniq
    all_errors = child_results.all? { |result| result[:status] == 'error' }

    {
      status: all_errors ? 'error' : 'ok',
      result_type: 'multi_search',
      result_count: child_results.sum { |result| result_count_for(result) },
      queries: child_results,
      warnings: warnings
    }.tap do |payload|
      next unless all_errors

      payload[:error_code] = 'catalog_multi_search_failed'
      payload[:error_message] = 'Ikas catalog search failed.'
    end
  end

  def child_result_payload(query, result)
    result = result.to_h.deep_symbolize_keys
    result[:query] = query if result[:query].blank?
    result[:warnings] = Array(result[:warnings])
    result[:result_count] = result_count_for(result)
    result
  end

  def result_count_for(result)
    result[:result_count].presence || Array(result[:candidates]).length
  end

  attr_reader :ai_agent, :account, :mode, :settings
end
