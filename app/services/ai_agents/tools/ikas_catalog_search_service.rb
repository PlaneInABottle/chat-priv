# frozen_string_literal: true

require Rails.root.join('lib/integrations/ikas/catalog')

class AiAgents::Tools::IkasCatalogSearchService
  def initialize(ai_agent:, account:, mode:, settings:, **context)
    @ai_agent = ai_agent
    @account = account
    @mode = mode
    @settings = settings || {}
    @trigger_message = context[:trigger_message]
  end

  def call(args:)
    Integrations::Ikas::CatalogSearchService.new(
      account: account,
      query_text: expanded_query_text(args['query']),
      context_query_text: nil,
      limit: args['limit'].presence || Integrations::Ikas::CatalogSearchService::DEFAULT_LIMIT
    ).call
  end

  private

  attr_reader :ai_agent, :account, :mode, :settings, :trigger_message

  def expanded_query_text(query_text)
    current_text = trigger_message&.content.to_s
    return query_text if current_text.blank?

    query_terms = catalog_terms_for(query_text)
    current_terms = catalog_terms_for(current_text)
    return current_text if narrower_than_customer_phrase?(query_terms, current_terms)

    query_text
  end

  def narrower_than_customer_phrase?(query_terms, current_terms)
    query_terms.any? &&
      current_terms.length > query_terms.length &&
      (query_terms - current_terms).empty?
  end

  def catalog_terms_for(text)
    Integrations::Ikas::Catalog::QueryParser.terms_for(text)
  end
end
