# frozen_string_literal: true

class AiAgents::LlmAdapters::BaseAdapter
  def initialize(ai_agent:, account:, prompt_override: nil, config_override: nil, improvement_operation: nil, initiated_by: nil, # rubocop:disable Metrics/ParameterLists
                 knowledge_sources_override: nil, llm_options: {})
    @ai_agent = ai_agent
    @account = account
    @prompt_override = prompt_override
    @config_override = config_override
    @improvement_operation = improvement_operation
    @initiated_by = initiated_by
    @knowledge_sources_override = knowledge_sources_override
    @system_prompt_override = llm_options[:system_prompt]
    @max_tokens = llm_options[:max_tokens]
    @temperature = llm_options[:temperature]
    @response_format = llm_options[:response_format]
  end

  def perform(messages:, tools:, tool_choice: 'auto')
    raise NotImplementedError
  end

  private

  attr_reader :ai_agent, :account, :prompt_override, :config_override, :system_prompt_override, :max_tokens, :temperature,
              :response_format, :improvement_operation, :initiated_by, :knowledge_sources_override

  def system_prompt
    return system_prompt_override if system_prompt_override

    AiAgents::PromptComposer.new(
      ai_agent: ai_agent,
      prompt_override: prompt_override,
      config_override: config_override,
      knowledge_sources_override: knowledge_sources_override
    ).effective_system_prompt
  end
end
