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
      reason: {
        type: 'string',
        description: 'Short internal reason for why automated assistance should stop.'
      },
      customer_message: {
        type: 'string',
        description: 'Public message sent to the customer before automation stops. Write it naturally as brand support copy and keep operational details in internal_note.'
      },
      internal_note: {
        type: 'string',
        description: 'Private note for the human agent with the useful context needed to continue.'
      },
      labels: {
        type: 'array',
        items: { type: 'string' },
        description: 'Optional labels to apply. Use only configured or existing account labels.'
      }
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
    'organic products, product links, related product selection, or follow-up references.',
    'Use a self-contained catalog query with product/category context and hard constraints,',
    'not filler or action words from the customer message.'
  ].join(' ').freeze

  IKAS_CATALOG_SEARCH_INPUT_SCHEMA = {
    type: 'object',
    properties: {
      query: {
        type: 'string',
        description: [
          'A complete catalog search phrase for the connected seller catalog.',
          'Use query for one search or queries for up to three related searches; prefer one field, not both.',
          'For follow-ups, include previous product/category context yourself, for example',
          '"70x80 akordiyon sineklik" or "beyaz plise perde", not only "70x80" or "beyaz".',
          'Drop filler/action words such as "kral", "abi", "şey", "link", "fiyat", and "en ucuz"',
          'unless they are part of a real product name.',
          'Drop purchase quantities such as "2 tane" unless they are part of a product pack, product name, or dimensions.'
        ].join(' ')
      },
      queries: {
        type: 'array',
        items: { type: 'string' },
        maxItems: 3,
        description: [
          'Up to three complete, self-contained catalog search phrases for related catalog lookups.',
          'Use this instead of query when multiple independent product/category searches are needed.',
          'Each query should include product/category context and hard constraints.'
        ].join(' ')
      },
      limit: { type: 'integer', minimum: 1, maximum: 20, default: 8 }
    },
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
