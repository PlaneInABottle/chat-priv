# frozen_string_literal: true

class AiAgents::Tools::IkasLookupOrderService
  def initialize(ai_agent:, account:, mode:, settings:, **context)
    @ai_agent = ai_agent
    @account = account
    @mode = mode
    @settings = settings || {}
    @conversation = context[:conversation]
    @trigger_message = context[:trigger_message]
  end

  def call(**kwargs)
    args = kwargs.fetch(:args, {}) || {}

    Integrations::Ikas::OrderLookupService.new(
      account: account,
      conversation: conversation,
      identifiers: args.slice('order_identifier', 'email', 'phone'),
      limit: args['limit'].presence || Integrations::Ikas::OrderLookupService::DEFAULT_LIMIT
    ).call
  end

  private

  attr_reader :account, :conversation
end
