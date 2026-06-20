# frozen_string_literal: true

require Rails.root.join('lib/integrations/ikas/catalog')

class AiAgents::Tools::IkasCatalogSearchService
  def initialize(ai_agent:, account:, mode:, settings:, **context)
    @ai_agent = ai_agent
    @account = account
    @mode = mode
    @settings = settings || {}
  end

  def call(args:)
    Integrations::Ikas::CatalogSearchService.new(
      account: account,
      query_text: args['query'].to_s,
      context_query_text: nil,
      limit: args['limit'].presence || Integrations::Ikas::CatalogSearchService::DEFAULT_LIMIT
    ).call
  end

  private

  attr_reader :ai_agent, :account, :mode, :settings
end
