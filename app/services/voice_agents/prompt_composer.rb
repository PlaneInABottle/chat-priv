# frozen_string_literal: true

class VoiceAgents::PromptComposer
  BASE_PROMPT = <<~PROMPT
    You are %<installation_name>s's customer support voice assistant.
    Speak naturally and keep answers short enough for a phone call.
    Ask one clarification question at a time.
    Do not read long product links, identifiers, or JSON aloud.
    Treat unclear or multilingual-looking speech as possible speech-to-text noise.
    Do not switch languages or infer a foreign-language request unless the caller clearly asks.
    If the voice language is Turkish, prefer a plausible Turkish interpretation and ask a short Turkish clarification when unsure.
    If a caller asks for a human, call `request_human_handoff`.
    If the conversation is complete and the caller is ready to finish, call `end_customer_call`.
  PROMPT

  def initialize(voice_agent:)
    @voice_agent = voice_agent
  end

  def effective_system_prompt
    [
      base_prompt,
      global_instructions_prompt,
      language_prompt,
      greeting_prompt,
      agent_prompt,
      tool_policy_prompt
    ].compact.join("\n\n")
  end

  private

  attr_reader :voice_agent

  def base_prompt
    installation_name = GlobalConfigService.load('INSTALLATION_NAME', 'Chatwoot').presence || 'Chatwoot'
    format(BASE_PROMPT, installation_name: installation_name)
  end

  def global_instructions_prompt
    instructions = AiAgents::Settings.global_instructions
    return if instructions.blank?

    "Platform global AI instructions:\n#{instructions}"
  end

  def language_prompt
    return if voice_agent.language.blank?

    "Voice language: #{voice_agent.language}. Use this language unless the caller clearly asks otherwise."
  end

  def greeting_prompt
    return if voice_agent.greeting.blank?

    "Preferred greeting: #{voice_agent.greeting}"
  end

  def agent_prompt
    return if voice_agent.prompt.blank?

    "Voice agent instructions:\n#{voice_agent.prompt}"
  end

  def tool_policy_prompt
    policies = [AiAgents::ToolPromptPolicy.new(enabled_tool_keys).instructions.presence]
    policies << voice_link_policy if enabled_tool_keys.include?(VoiceAgents::Config::IKAS_CATALOG_SEARCH_TOOL)
    policies.compact.join("\n").presence
  end

  def voice_link_policy
    <<~PROMPT
      Voice product-link rule:
      - If product links are returned by a tool, do not read the full URL aloud. Say that matching links are available in the support panel or can be sent later.
    PROMPT
  end

  def enabled_tool_keys
    @enabled_tool_keys ||= VoiceAgents::Config.new(voice_agent.tools_config).enabled_tool_keys
  end
end
