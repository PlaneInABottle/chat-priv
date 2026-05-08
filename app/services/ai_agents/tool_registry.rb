# frozen_string_literal: true

module AiAgents
  class ToolRegistry
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

    def self.available_definitions
      @available_definitions ||= [human_handoff_definition, ikas_lookup_order_definition]
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
        input_schema: {
          type: 'object',
          properties: {
            reason: { type: 'string' },
            customer_message: { type: 'string' },
            internal_note: { type: 'string' },
            labels: { type: 'array', items: { type: 'string' } }
          },
          required: %w[reason customer_message internal_note],
          additionalProperties: false
        },
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
        description: 'Look up order details from ikas when the account integration is connected.',
        input_schema: {
          type: 'object',
          properties: {
            order_identifier: { type: 'string' }
          },
          required: ['order_identifier'],
          additionalProperties: false
        },
        mode_support: 'test_only',
        requires_integration_app_id: Integrations::Ikas::ConnectionStatus::IKAS_APP_ID,
        terminal: false,
        service_class: 'AiAgents::Tools::IkasLookupOrderService'
      )
    end
  end
end
