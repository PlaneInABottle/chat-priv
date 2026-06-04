# frozen_string_literal: true

class AiAgents::ToolPromptPolicy
  IKAS_CATALOG_RULES = <<~PROMPT
    Catalog tool rules:
    - Use `ikas_catalog_search` before answering questions about products, availability, dimensions, compatible sizes, colors, sizes, variants, categories, price, weight, volume, or organic products.
    - Answer only from the catalog tool result. Do not invent products, prices, sizes, colors, stock, dimensions, or compatibility.
    - If the result_type is `clarify_category`, ask a focused question using the returned buckets.
    - If the result_type is `show_compatible_candidates`, explain why the candidate fits. For dimensions, mention the catalog max/range evidence.
    - If the result_type is `no_match`, say no clear match was found and ask for clarification or suggest human handoff.
    - Do not say a product is in stock unless stock.in_stock is true. If stock.sellable is true but stock.in_stock is false, say it can be ordered instead.
    - Do not mention a price currency when price.currency is blank. If the customer asks about price and currency is blank, say the catalog returned the amount without currency.
  PROMPT

  IKAS_ORDER_RULES = <<~PROMPT
    Order lookup tool rules:
    - Use `ikas_lookup_order` before answering questions about order status, shipment, cargo, tracking number, tracking link, payment status, or package fulfillment.
    - You may call it with an order number, email, or phone number the customer provided. If none is provided, call it with `{}` so it can use the current Chatwoot contact identifiers.
    - Answer only from the order lookup tool result. Do not invent cargo company, tracking number, tracking link, order status, payment status, package status, dates, or totals.
    - If the result_type is `needs_identifier`, ask for order number, phone number, or email address.
    - If the result_type is `clarify_order`, ask which returned order number the customer means.
    - If the result_type is `show_order_status`, summarize the order/package/payment status and include tracking details only when returned.
    - If the result_type is `no_match`, say no matching order was found and ask the customer to check the identifier or request human help.
    - Never reveal customer email, phone, billing address, shipping address, or unrelated customer profile data.
  PROMPT

  def initialize(enabled_tool_keys)
    @enabled_tool_keys = Array(enabled_tool_keys).map(&:to_s)
  end

  def instructions
    policies = []
    policies << IKAS_CATALOG_RULES if enabled_tool_keys.include?(AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL)
    policies << IKAS_ORDER_RULES if enabled_tool_keys.include?(AiAgents::Config::IKAS_LOOKUP_ORDER_TOOL)
    policies.join("\n").presence
  end

  private

  attr_reader :enabled_tool_keys
end
