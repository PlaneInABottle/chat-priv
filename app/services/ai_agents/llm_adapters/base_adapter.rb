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
        AiAgents::ResponseService::SYSTEM_PROMPT_TEMPLATE % { prompt: ai_agent.prompt }
      end
    end
  end
end
