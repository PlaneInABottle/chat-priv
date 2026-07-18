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
      reason: { type: 'string', description: 'Short internal reason for why automated assistance should stop. Use the customer conversation language.' },
      customer_message: {
        type: 'string',
        description: 'Public message sent before automation stops, written naturally in the same language as the latest customer message. ' \
                     'Keep operational details in internal_note.'
      },
      internal_note: {
        type: 'string',
        description: [
          'Private context for the human teammate, in the customer conversation language. In 1-3 concise sentences, state the customer goal,',
          'relevant facts already provided, actions attempted and their outcome, and the recommended next step.',
          'Do not repeat the public transfer message or the latest customer message.'
        ].join(' ')
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
    'Use a self-contained catalog query with product/category terms and catalog-identifying attributes or measurements,',
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
          'For ambiguous follow-ups, include the relevant product/category context yourself; do not send only a color, size, or measurement.',
          'If the customer only gave dimensions and there is no previous product/category context, ask a clarifying question instead of adding a guessed product/category.',
          'Write catalog search terms rather than copying the customer sentence.',
          'For budget or availability preferences, search the product scope and reason over the returned price and stock fields.',
          'Drop purchase quantities unless they are part of a product pack, product name, or dimensions.'
        ].join(' ')
      },
      queries: {
        type: 'array',
        items: { type: 'string' },
        maxItems: 3,
        description: [
          'Up to three complete, self-contained catalog search phrases for related catalog lookups.',
          'Use this instead of query when multiple independent product/category searches are needed.',
          'Each query should include product/category context and catalog-identifying attributes or measurements.'
        ].join(' ')
      },
      limit: { type: 'integer', minimum: 1, maximum: 20, default: 8 }
    },
    additionalProperties: false
  }.freeze

  KNOWLEDGE_SEARCH_DESCRIPTION = [
    'Search the assistant selected verified knowledge sources before answering business facts, policies, services, or support questions.',
    'Use a short query with the important customer terms and relevant synonyms.',
    'Treat returned excerpts as the only verified evidence for the answer.'
  ].join(' ').freeze

  KNOWLEDGE_SEARCH_INPUT_SCHEMA = {
    type: 'object',
    properties: {
      query: {
        type: 'string',
        maxLength: AiKnowledgeSources::Retriever::MAX_QUERY_LENGTH,
        description: 'A concise search query using the important customer terms and useful synonyms.'
      },
      limit: { type: 'integer', minimum: 1, maximum: AiKnowledgeSources::Retriever::MAX_LIMIT, default: 3 }
    },
    required: ['query'],
    additionalProperties: false
  }.freeze

  def self.available_definitions
    @available_definitions ||= [human_handoff_definition, AiAgents::ToolDefinitions::PresentOptions.build(Definition),
                                AiAgents::ToolDefinitions::PresentCatalogProducts.build(Definition),
                                ikas_lookup_order_definition, ikas_catalog_search_definition]
  end

  def self.runtime_definitions
    @runtime_definitions ||= [*available_definitions, knowledge_search_definition]
  end

  def self.keys = available_definitions.map(&:key)

  def self.find(tool_key)
    runtime_definitions.find { |definition| definition.key == tool_key.to_s || definition.name == tool_key.to_s }
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

  def self.knowledge_search_definition
    Definition.new(
      key: AiAgents::Config::KNOWLEDGE_SEARCH_TOOL,
      name: AiAgents::Config::KNOWLEDGE_SEARCH_TOOL,
      description: KNOWLEDGE_SEARCH_DESCRIPTION,
      input_schema: KNOWLEDGE_SEARCH_INPUT_SCHEMA,
      mode_support: 'both',
      requires_integration_app_id: nil,
      terminal: false,
      service_class: 'AiAgents::Tools::KnowledgeSearchService'
    )
  end
end
