# frozen_string_literal: true

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
      query_text: args['query'],
      limit: args['limit'].presence || Integrations::Ikas::CatalogSearchService::DEFAULT_LIMIT
    ).call
  end

  private

  attr_reader :ai_agent, :account, :mode, :settings, :conversation, :trigger_message
end
