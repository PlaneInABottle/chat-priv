# frozen_string_literal: true

class AiAgents::ToolDefinitions::PresentCatalogProducts
  DESCRIPTION = [
    'Present one to three verified catalog products with their images and details.',
    'Use only after ikas_catalog_search and only when images materially help or the customer asks to see them.',
    'This displays products; it does not ask the customer to select an option.'
  ].join(' ').freeze

  INPUT_SCHEMA = {
    type: 'object',
    properties: {
      mode: {
        type: 'string',
        enum: %w[products product_gallery],
        description: 'Use products for distinct products and product_gallery for more photos of exactly one product.'
      },
      catalog_item_ids: {
        type: 'array',
        minItems: 1,
        maxItems: 3,
        items: { type: 'string' },
        description: 'Item IDs from the latest successful ikas_catalog_search result.'
      },
      customer_message: {
        type: 'string',
        maxLength: AiAgents::Tools::PresentCatalogProductsService::CUSTOMER_MESSAGE_LIMIT,
        description: 'A concise introduction in the customer language, written as the merchant and without mentioning searches or tools.'
      },
      continue_previous: {
        type: 'boolean',
        default: false,
        description: [
          'Set true when the customer asks for more products or additional photos after a previous presentation.',
          'Use new product IDs in products mode.'
        ].join(' ')
      }
    },
    required: %w[mode catalog_item_ids customer_message],
    additionalProperties: false
  }.freeze

  def self.build(definition_class)
    definition_class.new(
      key: AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL,
      name: AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL,
      description: DESCRIPTION,
      input_schema: INPUT_SCHEMA,
      mode_support: 'both',
      requires_integration_app_id: Integrations::Ikas::ConnectionStatus::IKAS_APP_ID,
      terminal: true,
      service_class: 'AiAgents::Tools::PresentCatalogProductsService'
    )
  end
end
