# frozen_string_literal: true

class AiAgents::LlmAdapters::BaseAdapter
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
    AiAgents::PromptComposer.new(ai_agent: ai_agent).effective_system_prompt
  end
end
