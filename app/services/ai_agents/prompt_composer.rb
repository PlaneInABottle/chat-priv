# frozen_string_literal: true

class AiAgents::PromptComposer
  def initialize(ai_agent:)
    @ai_agent = ai_agent
  end

  attr_reader :ai_agent

  def base_prompt
    AiAgents::Settings.global_instructions
  end

  def global_instructions_prompt
    nil
  end

  def agent_prompt
    return if ai_agent.prompt.blank?

    "AI agent instructions:\n#{ai_agent.prompt}"
  end

  def tool_policy_prompt
    AiAgents::ToolPromptPolicy.new(enabled_tool_keys).instructions
  end

  def effective_system_prompt
    [base_prompt, agent_prompt, tool_policy_prompt].compact.join("\n\n")
  end

  private

  def enabled_tool_keys
    tool_config.enabled_tool_keys
  end

  def tool_config
    @tool_config ||= AiAgents::Config.new(ai_agent.config, allow_legacy_human_handoff_settings: true)
  end
end
