# frozen_string_literal: true

class AiAgents::LlmCallLogger
  def initialize(ai_agent:, account:, conversation:, trigger_message:, mode:)
    @ai_agent = ai_agent
    @account = account
    @conversation = conversation
    @trigger_message = trigger_message
    @mode = mode
  end

  def call(step:, model:, request_messages:, request_tools:, status:, response: {}, request_options: {}, error: nil, duration_ms: nil)
    AiAgentLlmCall.create!(
      account: account,
      ai_agent: ai_agent,
      conversation: loggable_conversation,
      message: loggable_message,
      model: model,
      step: step,
      mode: mode.to_s,
      status: status,
      request_messages: sanitized_messages(request_messages),
      request_tool_names: tool_names(request_tools),
      response: sanitized_response(response, request_options),
      usage: response[:usage] || response['usage'] || {},
      finish_reason: response[:finish_reason] || response['finish_reason'],
      error_code: error&.class&.name,
      error_message: error&.message,
      duration_ms: duration_ms
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

  def sanitized_messages(messages)
    Array(messages).map do |message|
      message.deep_stringify_keys.slice('role', 'content', 'tool_calls', 'tool_call_id')
    end
  end

  def tool_names(tools)
    Array(tools).filter_map { |tool| tool.dig(:function, :name) || tool.dig('function', 'name') }
  end

  def sanitized_response(response, request_options)
    payload = response.except(:raw_response, 'raw_response', :usage, 'usage').deep_stringify_keys
    options = request_options.to_h.deep_stringify_keys.slice('max_tokens')
    payload['request_options'] = options if options.present?
    payload
  end
end
