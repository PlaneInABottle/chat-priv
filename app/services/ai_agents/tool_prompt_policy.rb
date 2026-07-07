# frozen_string_literal: true

class AiAgents::ToolPromptPolicy
  IKAS_CATALOG_RULES = <<~PROMPT
    Catalog tool rules:
    - Use `ikas_catalog_search` before answering questions about products, availability, dimensions, compatible sizes, colors, sizes, variants, categories, price, weight, volume, organic products, product links, or follow-up references to a previous product option.
    - For independent product/category questions in one customer message, prefer one `ikas_catalog_search` call with `queries` containing up to three self-contained catalog queries.
    - Tool queries must be self-contained. For ambiguous follow-ups, include the relevant product/category context yourself; do not send only a color, size, or measurement.
    - If the latest customer message only gives dimensions or measurements and there is no clear previous product/category context, do not guess a product/category. Ask which product/category the dimensions are for.
    - The latest customer message controls product/category scope. If it names a product or category, search that scope and do not carry over the previous product/category.
    - Use previous product/category context only when the latest message is ambiguous and does not name a new product/category.
    - When the latest message introduces another named product/category, treat it as a new topic unless the customer explicitly asks to compare or combine it with the previous topic.
    - For a new named topic, do not add the previous product/category as an extra `queries` entry and do not answer the previous topic.
    - Keep only catalog terms and hard constraints in the query. Drop filler/action words unless they are part of a real product name.
    - Do not include purchase quantity words in catalog queries unless the quantity is part of the product name, pack size, or requested dimensions.
    - Prefer one precise catalog search. If it returns `no_match`, you may make at most one simpler fallback search that keeps the main product/category and hard constraints.
    - Answer only from the catalog tool result. Do not invent products, prices, sizes, colors, stock, dimensions, or compatibility.
    - If result_type is `multi_search`, answer from the per-query results and keep each product/category recommendation tied to its returned query.
    - Do not tell the customer that you used tools, ran searches, checked a database, have a tool budget, or are answering from "search results"; just answer naturally from the available catalog evidence.
    - If the result_type is `clarify_category`, ask one short focused question using at most three relevant returned buckets. Do not list every bucket.
    - If the result_type is `needs_scope`, ask which product or category the customer means. Do not suggest example products or categories unless they were returned by the tool.
    - If the customer asks for a link or a specific option and the tool returns multiple matching candidates, do not guess. Ask a focused clarification using the returned candidate display names.
    - If the result_type is `show_compatible_candidates`, explain why the candidate fits. For dimensions, mention the catalog max/range evidence.
    - If the result_type is `no_match`, say no clear match was found. Ask for clarification or suggest the closest real returned alternatives only if a returned result includes candidates. Do not list store categories, previous products, or examples unless the tool returned them or the customer asked for alternatives.
    - For unavailable, impossible, or unrealistic product requests, stay professional. Do not joke, tease, or comment on the customer's intent.
    - Use stock evidence to avoid recommending unavailable products. Do not mention that an item is in stock unless availability is the customer question or it changes the recommendation.
    - Do not say a product is in stock unless stock.in_stock is true. If stock.sellable is true but stock.in_stock is false, say it can be ordered instead.
    - Answer in natural support prose. Avoid robotic field-label blocks such as product/stock/color/price lines unless the customer explicitly asks for a structured table.
    - Never write ₺, TL, TRY, $, €, or any currency symbol/code unless price.currency is present on that candidate. If price.currency is blank, write the amount followed by "(para birimi belirtilmemiş)".
    - Treat price.amount as the only final/current price. If price.final_total_known is false, do not present or repeat price.reference_amount or price.compare_at_reference_amount; say the final price depends on selected options or dimensions and share the product link or ask a focused follow-up.
    - If the customer quotes a visible/reference/unit price for a custom-option product, do not repeat the numeric amount or attach a currency to it. Refer to it as "gördüğünüz tutar" or "listed reference amount", and explain it is not a final total.
    - If price.compare_at_amount is present with price.amount, answer with price.amount as the current price and mention the higher compare-at price only when it helps clarify a discount.
    - If the customer asks for product links, include `candidate.link.url` when it exists. Never invent, guess, or construct product links yourself.
    - If handoff is needed in the same response as another tool, call only `human_handoff`; the handoff will stop automation.
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
    - If handoff is needed in the same response as another tool, call only `human_handoff`; the handoff will stop automation.
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
