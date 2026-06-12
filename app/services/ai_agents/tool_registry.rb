# frozen_string_literal: true

class AiAgents::ToolRegistry
  Definition = Struct.new(
    :key,
    :name,
    :description,
    :input_schema,
    :mode_support,
    :requires_integration_app_id,
    :terminal,
    :service_class,
    keyword_init: true
  )

  HUMAN_HANDOFF_INPUT_SCHEMA = {
    type: 'object',
    properties: {
      reason: { type: 'string' },
      customer_message: { type: 'string' },
      internal_note: { type: 'string' },
      labels: { type: 'array', items: { type: 'string' } }
    },
    required: %w[reason customer_message internal_note],
    additionalProperties: false
  }.freeze

  IKAS_LOOKUP_ORDER_DESCRIPTION = [
    'Look up order and cargo status from the connected ikas store using an order number,',
    'customer email, customer phone, or the current conversation contact identifiers.'
  ].join(' ').freeze

  IKAS_LOOKUP_ORDER_INPUT_SCHEMA = {
    type: 'object',
    properties: {
      order_identifier: {
        type: 'string',
        description: 'Customer-provided ikas order number or order ID, if available.'
      },
      email: {
        type: 'string',
        description: 'Customer-provided email address, if available.'
      },
      phone: {
        type: 'string',
        description: 'Customer-provided phone number, preferably in international format.'
      },
      limit: { type: 'integer', minimum: 1, maximum: 10, default: 5 }
    },
    additionalProperties: false
  }.freeze

  IKAS_CATALOG_SEARCH_DESCRIPTION = [
    'Search the connected ikas catalog before answering customer questions about product availability,',
    'dimensions, compatible sizes, colors, sizes, variants, categories, price, weight, volume,',
    'organic products, product links, related product selection, or follow-up references to a',
    'previously discussed product option such as a color, size, model, or "that one".',
    'The query must be self-contained: include the relevant product/category/type words yourself',
    'and omit unrelated filler, shopping, or sorting words from the customer message.'
  ].join(' ').freeze

  IKAS_CATALOG_SEARCH_INPUT_SCHEMA = {
    type: 'object',
    properties: {
      query: {
        type: 'string',
        description: [
          'A complete catalog search phrase for the connected seller catalog.',
          'For follow-ups, include the previous product/category context and requested option yourself,',
          'for example "70x80 akordiyon sineklik" or "beyaz plise perde", not only "70x80" or "beyaz".',
          'Do not include unrelated conversational filler words such as "kral", "abi", "ya", "şey", "yani", or "işte".',
          'Do not include action, shopping, or sorting words such as "link", "en ucuz", "ucuz", "uygun", or "fiyat",',
          'unless they are part of a real product name. If a detailed query has no match, retry at most once with a simpler',
          'main product/category query that keeps hard constraints such as dimensions, color, size, or weight.'
        ].join(' ')
      },
      limit: { type: 'integer', minimum: 1, maximum: 20, default: 8 }
    },
    required: ['query'],
    additionalProperties: false
  }.freeze

  def self.available_definitions
    @available_definitions ||= [human_handoff_definition, ikas_lookup_order_definition, ikas_catalog_search_definition]
  end

  def self.keys
    available_definitions.map(&:key)
  end

  def self.find(tool_key)
    available_definitions.find { |definition| definition.key == tool_key.to_s }
  end

  def self.human_handoff_definition
    Definition.new(
      key: AiAgents::Config::HUMAN_HANDOFF_TOOL,
      name: 'human_handoff',
      description: 'Hand off the conversation to a human agent when automated assistance should stop.',
      input_schema: HUMAN_HANDOFF_INPUT_SCHEMA,
      mode_support: 'both',
      requires_integration_app_id: nil,
      terminal: true,
      service_class: 'AiAgents::Tools::HumanHandoffService'
    )
  end

  def self.ikas_lookup_order_definition
    Definition.new(
      key: AiAgents::Config::IKAS_LOOKUP_ORDER_TOOL,
      name: 'ikas_lookup_order',
      description: IKAS_LOOKUP_ORDER_DESCRIPTION,
      input_schema: IKAS_LOOKUP_ORDER_INPUT_SCHEMA,
      mode_support: 'both',
      requires_integration_app_id: Integrations::Ikas::ConnectionStatus::IKAS_APP_ID,
      terminal: false,
      service_class: 'AiAgents::Tools::IkasLookupOrderService'
    )
  end

  def self.ikas_catalog_search_definition
    Definition.new(
      key: AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL,
      name: 'ikas_catalog_search',
      description: IKAS_CATALOG_SEARCH_DESCRIPTION,
      input_schema: IKAS_CATALOG_SEARCH_INPUT_SCHEMA,
      mode_support: 'both',
      requires_integration_app_id: Integrations::Ikas::ConnectionStatus::IKAS_APP_ID,
      terminal: false,
      service_class: 'AiAgents::Tools::IkasCatalogSearchService'
    )
  end
end
