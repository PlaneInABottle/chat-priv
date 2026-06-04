# frozen_string_literal: true

module AiAgents
  module LlmAdapters
    class BaseAdapter
      def initialize(ai_agent:, account:)
        @ai_agent = ai_agent
        @account = account
      end

      def perform(messages:, tools:, tool_choice: 'auto')
        raise NotImplementedError
      end

      private

      attr_reader :ai_agent, :account

      def system_prompt
        base_prompt = format(AiAgents::ResponseService::SYSTEM_PROMPT_TEMPLATE, prompt: ai_agent.prompt)
        tool_policy = AiAgents::ToolPromptPolicy.new(tool_config.enabled_tool_keys).instructions

        [base_prompt, tool_policy].compact.join("\n")
      end

      def tool_config
        @tool_config ||= AiAgents::Config.new(ai_agent.config, allow_legacy_human_handoff_settings: true)
      end
    end
  end
end
