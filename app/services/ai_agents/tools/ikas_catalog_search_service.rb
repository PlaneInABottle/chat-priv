# frozen_string_literal: true

require Rails.root.join('lib/integrations/ikas/catalog')

class AiAgents::Tools::IkasCatalogSearchService
  def initialize(ai_agent:, account:, mode:, settings:, **context)
    @ai_agent = ai_agent
    @account = account
    @mode = mode
    @settings = settings || {}
    @conversation = context[:conversation]
    @trigger_message = context[:trigger_message]
  end

  def call(args:)
    Integrations::Ikas::CatalogSearchService.new(
      account: account,
      query_text: expanded_query_text(args['query']),
      context_query_text: recent_customer_contexts,
      limit: args['limit'].presence || Integrations::Ikas::CatalogSearchService::DEFAULT_LIMIT
    ).call
  end

  private

  attr_reader :ai_agent, :account, :mode, :settings, :conversation, :trigger_message

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

  def recent_customer_contexts
    return if conversation.blank?

    recent_incoming_messages.map(&:content).reverse.presence
  end

  def recent_incoming_messages
    scope = conversation.messages.incoming.where.not(content: [nil, ''])
    scope = scope.where.not(id: trigger_message.id) if trigger_message&.id
    scope = scope.where('created_at <= ?', trigger_message.created_at) if trigger_message&.created_at
    scope.reorder(created_at: :desc, id: :desc).limit(8)
  end
end
