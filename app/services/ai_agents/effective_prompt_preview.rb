# frozen_string_literal: true

class AiAgents::EffectivePromptPreview
  def initialize(ai_agent:)
    @ai_agent = ai_agent
  end

  attr_reader :ai_agent

  delegate :account, to: :ai_agent

  def model
    account.ai_agent_model
  end

  def enabled_tool_keys
    tool_config.enabled_tool_keys
  end

  def enabled_tool_definitions
    enabled_tool_keys.filter_map { |tool_key| AiAgents::ToolRegistry.find(tool_key) }
  end

  def base_prompt
    prompt_composer.base_prompt
  end

  def global_instructions_prompt
    prompt_composer.global_instructions_prompt
  end

  def agent_prompt
    prompt_composer.agent_prompt
  end

  def tool_policy_prompt
    prompt_composer.tool_policy_prompt
  end

  def effective_system_prompt
    prompt_composer.effective_system_prompt
  end

  def integration_gates
    enabled_tool_definitions.map { |definition| integration_gate_for(definition) }
  end

  private

  def tool_config
    @tool_config ||= AiAgents::Config.new(ai_agent.config, allow_legacy_human_handoff_settings: true)
  end

  def prompt_composer
    @prompt_composer ||= AiAgents::PromptComposer.new(ai_agent: ai_agent)
  end

  def integration_gate_for(definition)
    app_id = definition.requires_integration_app_id
    return no_integration_gate(definition) if app_id.blank?
    return ikas_integration_gate(definition) if app_id == Integrations::Ikas::ConnectionStatus::IKAS_APP_ID

    generic_integration_gate(definition, app_id)
  end

  def no_integration_gate(definition)
    {
      tool_key: definition.key,
      required: false,
      app_id: nil,
      state: 'not_required',
      store_host: nil,
      error_code: nil
    }
  end

  def ikas_integration_gate(definition)
    payload = Integrations::Ikas::ConnectionStatus.new(account: account).payload

    {
      tool_key: definition.key,
      required: true,
      app_id: Integrations::Ikas::ConnectionStatus::IKAS_APP_ID,
      state: payload[:state],
      store_host: payload[:store_host],
      error_code: payload[:last_validation_error_code]
    }
  end

  def generic_integration_gate(definition, app_id)
    hook = account.hooks.find_by(app_id: app_id)

    {
      tool_key: definition.key,
      required: true,
      app_id: app_id,
      state: hook&.status || 'not_connected',
      store_host: hook&.reference_id,
      error_code: nil
    }
  end
end
