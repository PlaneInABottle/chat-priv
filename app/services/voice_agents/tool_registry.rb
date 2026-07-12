# frozen_string_literal: true

class VoiceAgents::ToolRegistry
  END_CUSTOMER_CALL_INPUT_SCHEMA = {
    type: 'object',
    properties: {
      reason: { type: 'string' }
    },
    required: ['reason'],
    additionalProperties: false
  }.freeze

  def self.available_definitions
    @available_definitions ||= [
      human_handoff_definition,
      AiAgents::ToolRegistry.ikas_lookup_order_definition,
      AiAgents::ToolRegistry.ikas_catalog_search_definition,
      end_customer_call_definition
    ]
  end

  def self.keys
    available_definitions.map(&:key)
  end

  def self.runtime_definitions
    @runtime_definitions ||= [*available_definitions, AiAgents::ToolRegistry.knowledge_search_definition]
  end

  def self.find(tool_key)
    runtime_definitions.find { |definition| definition.key == tool_key.to_s || definition.name == tool_key.to_s }
  end

  def self.end_customer_call_definition
    AiAgents::ToolRegistry::Definition.new(
      key: VoiceAgents::Config::END_CUSTOMER_CALL_TOOL,
      name: 'end_customer_call',
      description: 'End the current customer call when the voice conversation is complete.',
      input_schema: END_CUSTOMER_CALL_INPUT_SCHEMA,
      mode_support: 'both',
      requires_integration_app_id: nil,
      terminal: true,
      service_class: nil
    )
  end

  def self.human_handoff_definition
    base = AiAgents::ToolRegistry.human_handoff_definition
    definition_from(base, name: 'request_human_handoff')
  end

  def self.definition_from(base, overrides = {})
    AiAgents::ToolRegistry::Definition.new(
      key: overrides.fetch(:key, base.key),
      name: overrides.fetch(:name, base.name),
      description: overrides.fetch(:description, base.description),
      input_schema: overrides.fetch(:input_schema, base.input_schema),
      mode_support: overrides.fetch(:mode_support, base.mode_support),
      requires_integration_app_id: overrides.fetch(:requires_integration_app_id, base.requires_integration_app_id),
      terminal: overrides.fetch(:terminal, base.terminal),
      service_class: overrides.fetch(:service_class, base.service_class)
    )
  end
end
