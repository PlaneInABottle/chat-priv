# frozen_string_literal: true

class AiAgents::PromptComposer
  def initialize(ai_agent:, prompt_override: nil)
    @ai_agent = ai_agent
    @prompt_override = prompt_override
  end

  attr_reader :ai_agent, :prompt_override

  def base_prompt
    AiAgents::Settings.global_instructions
  end

  def global_instructions_prompt
    nil
  end

  def agent_prompt
    prompt = prompt_override.nil? ? ai_agent.prompt : prompt_override
    return if prompt.blank?

    "AI agent instructions:\n#{prompt}"
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
