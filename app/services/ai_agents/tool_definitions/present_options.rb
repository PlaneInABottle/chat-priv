# frozen_string_literal: true

class AiAgents::ToolDefinitions::PresentOptions
  DESCRIPTION = [
    'Ask the customer one single-choice question using native channel options',
    'when choosing among 2 to 10 concise alternatives will advance the conversation.',
    'Use general options for conversation or support-flow choices.',
    'For products, categories, colors, sizes, or variants, pass only IDs returned by the latest ikas_catalog_search result.'
  ].join(' ').freeze

  INPUT_SCHEMA = {
    type: 'object',
    properties: {
      question: {
        type: 'string',
        maxLength: 1024,
        description: 'One focused customer-facing question in the same language as the customer.'
      },
      options: {
        type: 'array',
        minItems: 2,
        maxItems: 10,
        items: {
          type: 'object',
          properties: { label: { type: 'string', maxLength: 72 } },
          required: ['label'],
          additionalProperties: false
        },
        description: 'General conversation or support-flow choices. Do not use for catalog facts.'
      },
      catalog_option_ids: {
        type: 'array',
        minItems: 2,
        maxItems: 10,
        items: { type: 'string' },
        description: 'Category or item IDs from the latest successful ikas_catalog_search result in this turn.'
      }
    },
    required: ['question'],
    additionalProperties: false
  }.freeze

  def self.build(definition_class)
    definition_class.new(
      key: AiAgents::Config::PRESENT_OPTIONS_TOOL,
      name: AiAgents::Config::PRESENT_OPTIONS_TOOL,
      description: DESCRIPTION,
      input_schema: INPUT_SCHEMA,
      mode_support: 'both',
      requires_integration_app_id: nil,
      terminal: true,
      service_class: 'AiAgents::Tools::PresentOptionsService'
    )
  end
end
