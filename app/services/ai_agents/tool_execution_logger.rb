# frozen_string_literal: true

class AiAgents::ToolExecutionLogger
  def initialize(ai_agent:, account:, conversation:, trigger_message:, mode:)
    @ai_agent = ai_agent
    @account = account
    @conversation = conversation
    @trigger_message = trigger_message
    @mode = mode
  end

  def call(tool_call:, definition:, status:, payload:)
    AiAgentToolExecution.create!(
      account: account,
      ai_agent: ai_agent,
      conversation: loggable_conversation,
      message: loggable_message,
      tool_key: tool_key(tool_call, definition),
      tool_name: definition&.name,
      mode: mode.to_s,
      status: status,
      error_code: error_code(payload[:tool_result]),
      error_message: error_message(payload[:tool_result]),
      tool_call_id: tool_call[:id],
      arguments: payload[:args] || {},
      result: sanitized_result(payload[:tool_result]),
      terminal: definition&.terminal || false,
      duration_ms: payload[:duration_ms]
    )
  end

  private

  attr_reader :ai_agent, :account, :conversation, :trigger_message, :mode

  def loggable_conversation
    conversation if conversation.is_a?(Conversation)
  end

  def loggable_message
    trigger_message if trigger_message.is_a?(Message)
  end

  def tool_key(tool_call, definition)
    definition&.key || tool_call[:name].to_s
  end

  def error_code(tool_result)
    tool_result[:error_code] || tool_result['error_code']
  end

  def error_message(tool_result)
    tool_result[:error_message] || tool_result['error_message']
  end

  def sanitized_result(tool_result)
    tool_result.except(:raw_response, 'raw_response').deep_stringify_keys
  end
end
