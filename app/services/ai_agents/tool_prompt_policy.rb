# frozen_string_literal: true

class AiAgents::ToolPromptPolicy
  IKAS_CATALOG_RULES = <<~PROMPT
    Catalog tool rules:
    - Use `ikas_catalog_search` before answering questions about products, availability, dimensions, compatible sizes, colors, sizes, variants, categories, price, weight, volume, organic products, product links, or follow-up references to a previous product option.
    - Tool queries must be self-contained. For follow-ups, include the relevant product/category context yourself, for example "70x80 akordiyon sineklik" or "beyaz plise perde".
    - Keep only catalog terms and hard constraints in the query. Drop filler/action words such as "kral", "abi", "şey", "link", "fiyat", "en ucuz", and "bakıyorum" unless they are part of a real product name.
    - Do not include purchase quantity words such as "2 tane", "iki adet", or "1 çift" in catalog queries unless the quantity is part of the product name, pack size, or requested dimensions.
    - Prefer one precise catalog search. If it returns `no_match`, make at most one simpler fallback search that keeps the main product/category and hard constraints.
    - Answer only from the catalog tool result. Do not invent products, prices, sizes, colors, stock, dimensions, or compatibility.
    - If the result_type is `clarify_category`, ask one short focused question using at most three relevant returned buckets. Do not list every bucket.
    - If the result_type is `needs_scope`, ask which product or category the customer means. Do not suggest example products or categories unless they were returned by the tool.
    - If the customer asks for a link or a specific option and the tool returns multiple matching candidates, do not guess. Ask a focused clarification using the returned candidate display names.
    - If the result_type is `show_compatible_candidates`, explain why the candidate fits. For dimensions, mention the catalog max/range evidence.
    - If the result_type is `no_match`, say no clear match was found and ask for clarification or suggest human handoff.
    - Do not say a product is in stock unless stock.in_stock is true. If stock.sellable is true but stock.in_stock is false, say it can be ordered instead.
    - Never write ₺, TL, TRY, $, €, or any currency symbol/code unless price.currency is present on that candidate. If price.currency is blank, write the amount followed by "(para birimi belirtilmemiş)".
    - If the customer asks for product links, include `candidate.link.url` when it exists. Never invent, guess, or construct product links yourself.
  PROMPT

  IKAS_ORDER_RULES = <<~PROMPT
    Order lookup tool rules:
    - Use `ikas_lookup_order` before answering questions about order status, shipment, cargo, tracking number, tracking link, payment status, or package fulfillment.
    - You may call it with an order number, email, or phone number the customer provided. If none is provided, call it with `{}` so it can use the current conversation contact identifiers.
    - Answer only from the order lookup tool result. Do not invent cargo company, tracking number, tracking link, order status, payment status, package status, dates, or totals.
    - If the result_type is `needs_identifier`, ask for order number, phone number, or email address.
    - If the result_type is `clarify_order`, ask which returned order number the customer means.
    - If the result_type is `show_order_status`, summarize the order/package/payment status and include tracking details only when returned.
    - If the result_type is `no_match`, say no matching order was found and ask the customer to check the identifier or request human help.
    - Never reveal or repeat customer email, phone, billing address, shipping address, or unrelated customer profile data, even if the customer provided it in the conversation. Refer to "the provided email" or "the provided phone number" instead.
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
