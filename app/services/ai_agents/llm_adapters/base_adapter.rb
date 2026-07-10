# frozen_string_literal: true

class AiAgents::LlmAdapters::BaseAdapter
  def initialize(ai_agent:, account:, prompt_override: nil, config_override: nil)
    @ai_agent = ai_agent
    @account = account
    @prompt_override = prompt_override
    @config_override = config_override
  end

  def perform(messages:, tools:, tool_choice: 'auto')
    raise NotImplementedError
  end

  private

  attr_reader :ai_agent, :account, :prompt_override, :config_override

  def system_prompt
    AiAgents::PromptComposer.new(
      ai_agent: ai_agent,
      prompt_override: prompt_override,
      config_override: config_override
    ).effective_system_prompt
  end
end
