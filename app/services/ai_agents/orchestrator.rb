# frozen_string_literal: true

require 'set'

module AiAgents
  class Orchestrator
    EMPTY_RESPONSE_RETRY_PROMPT = [
      'The previous AI response was empty.',
      'Reply to the latest customer message.',
      'If the answer requires an enabled tool, call exactly one tool.'
    ].join(' ').freeze
    CATALOG_NEEDS_SCOPE_MESSAGE = 'Hangi ürün veya kategori için bu ölçüyü soruyorsunuz?'.freeze

    def initialize(ai_agent:, messages:, mode:, conversation: nil, trigger_message: nil, adapter: nil)
      @ai_agent = ai_agent
      @messages = messages
      @mode = mode
      @conversation = conversation
      @trigger_message = trigger_message
      @adapter = adapter || default_adapter
      @config = AiAgents::Config.new(ai_agent.config, allow_legacy_human_handoff_settings: true)
      @executed_tool_keys = Set.new
    end

    def perform
      return failure_result unless ai_agent.enabled?
      return failure_result unless ai_agent.account.ai_agent_enabled?
      return failure_result unless config.valid?

      first_response = perform_llm_call(step: 'initial', request_messages: normalized_messages)

      return text_result(first_response) if first_response[:tool_calls].blank?
      return rejected_result('multiple_tool_calls') if first_response[:tool_calls].size > 1

      tool_execution = tool_executor.execute(first_response[:tool_calls].first)
      return rejected_tool_result(tool_execution.tool_event) if tool_execution.status == 'rejected'
      return terminal_result(first_response, tool_execution) if tool_execution.tool_result[:terminal_action].present?
      return tool_error_result(first_response, tool_execution) if tool_execution.status == 'error'
      return catalog_needs_scope_result(tool_execution) if catalog_needs_scope_tool_execution?(tool_execution)

      follow_up_response = perform_llm_call(
        step: 'tool_follow_up',
        request_messages: follow_up_messages(first_response, tool_execution)
      )

      return rejected_result('multiple_tool_calls_follow_up', [tool_execution.tool_event]) if follow_up_response[:tool_calls].present?

      {
        assistant_message: build_assistant_message(
          content: follow_up_response[:assistant_text].presence || first_response[:assistant_text].presence || fallback_assistant_message,
          tool_events: [tool_execution.tool_event]
        ),
        tool_events: [tool_execution.tool_event],
        terminal_action: nil
      }
    rescue StandardError => e
      Rails.logger.error("[AiAgents::Orchestrator] #{e.class}: #{e.message}")
      failure_result
    end

    private

    attr_reader :ai_agent, :messages, :mode, :conversation, :trigger_message, :adapter, :config, :executed_tool_keys

    def default_adapter
      AiAgents::LlmAdapters::OpenAiCompatibleAdapter.new(ai_agent: ai_agent, account: ai_agent.account)
    end

    def tool_executor
      @tool_executor ||= AiAgents::ToolExecutor.new(
        ai_agent: ai_agent,
        account: ai_agent.account,
        mode: mode,
        executed_tool_keys: executed_tool_keys,
        context: { conversation: conversation, trigger_message: trigger_message }
      )
    end

    def normalized_messages
      messages.map do |message|
        {
          role: message[:role] || message['role'],
          content: message[:content] || message['content']
        }
      end
    end

    def llm_tools
      @llm_tools ||= config.enabled_tool_keys.filter_map do |tool_key|
        definition = AiAgents::ToolRegistry.find(tool_key)
        next unless definition

        {
          type: 'function',
          function: {
            name: definition.name,
            description: definition.description,
            parameters: definition.input_schema
          }
        }
      end
    end

    def perform_llm_call(step:, request_messages:)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = adapter.perform(
        messages: request_messages,
        tools: llm_tools,
        tool_choice: 'auto'
      )
      log_llm_call(step: step, request_messages: request_messages, status: 'succeeded', response: response,
                   duration_ms: duration_ms(started_at))
      return retry_empty_llm_call(step: step, request_messages: request_messages) if empty_llm_response?(response)

      response
    rescue StandardError => e
      log_llm_call(step: step, request_messages: request_messages, status: 'failed', error: e, duration_ms: duration_ms(started_at))
      raise
    end

    def retry_empty_llm_call(step:, request_messages:)
      retry_messages = [*request_messages, { role: 'system', content: EMPTY_RESPONSE_RETRY_PROMPT }]
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = adapter.perform(
        messages: retry_messages,
        tools: llm_tools,
        tool_choice: 'auto'
      )
      log_llm_call(step: "#{step}_retry", request_messages: retry_messages, status: 'succeeded', response: response,
                   duration_ms: duration_ms(started_at))
      response
    rescue StandardError => e
      log_llm_call(step: "#{step}_retry", request_messages: retry_messages, status: 'failed', error: e,
                   duration_ms: duration_ms(started_at))
      raise
    end

    def empty_llm_response?(response)
      response[:assistant_text].blank? && response[:tool_calls].blank?
    end

    def log_llm_call(step:, request_messages:, status:, response: {}, error: nil, duration_ms: nil)
      llm_call_logger.call(
        step: step,
        model: ai_agent.account.ai_agent_model,
        request_messages: traced_request_messages(request_messages),
        request_tools: llm_tools,
        status: status,
        response: response,
        error: error,
        duration_ms: duration_ms
      )
    rescue StandardError => e
      Rails.logger.error("[AiAgents::LlmCallLogger] #{e.class}: #{e.message}")
    end

    def llm_call_logger
      @llm_call_logger ||= AiAgents::LlmCallLogger.new(
        ai_agent: ai_agent,
        account: ai_agent.account,
        conversation: conversation,
        trigger_message: trigger_message,
        mode: mode
      )
    end

    def traced_request_messages(request_messages)
      [{ role: 'system', content: effective_system_prompt }, *request_messages]
    end

    def effective_system_prompt
      @effective_system_prompt ||= AiAgents::EffectivePromptPreview.new(ai_agent: ai_agent).effective_system_prompt
    end

    def duration_ms(started_at)
      return unless started_at

      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end

    def text_result(response)
      return failure_result if response[:assistant_text].blank?

      {
        assistant_message: build_assistant_message(content: response[:assistant_text], tool_events: []),
        tool_events: [],
        terminal_action: nil
      }
    end

    def terminal_result(response, tool_execution)
      assistant_message = build_assistant_message(
        content: tool_execution.tool_result[:customer_message] || response[:assistant_text] || fallback_assistant_message,
        tool_events: [tool_execution.tool_event],
        terminal_action: tool_execution.tool_result[:terminal_action],
        tool_result: tool_execution.tool_result
      )

      {
        assistant_message: assistant_message,
        tool_events: [tool_execution.tool_event],
        terminal_action: tool_execution.tool_result[:terminal_action]
      }
    end

    def tool_error_result(response, tool_execution)
      {
        assistant_message: build_assistant_message(
          content: response[:assistant_text].presence || fallback_assistant_message,
          tool_events: [tool_execution.tool_event]
        ),
        tool_events: [tool_execution.tool_event],
        terminal_action: nil
      }
    end

    def catalog_needs_scope_result(tool_execution)
      {
        assistant_message: build_assistant_message(content: CATALOG_NEEDS_SCOPE_MESSAGE, tool_events: [tool_execution.tool_event]),
        tool_events: [tool_execution.tool_event],
        terminal_action: nil
      }
    end

    def catalog_needs_scope_tool_execution?(tool_execution)
      tool_execution.tool_event['tool'] == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL &&
        tool_execution.tool_result[:result_type].to_s == 'needs_scope'
    end

    def rejected_tool_result(tool_event)
      {
        assistant_message: build_assistant_message(content: fallback_assistant_message, tool_events: [tool_event]),
        tool_events: [tool_event],
        terminal_action: nil
      }
    end

    def rejected_result(error_code, tool_events = [])
      {
        assistant_message: build_assistant_message(content: fallback_assistant_message, tool_events: tool_events),
        tool_events: tool_events.presence || [{ 'status' => 'rejected', 'error_code' => error_code }],
        terminal_action: nil
      }
    end

    def failure_result
      {
        assistant_message: nil,
        tool_events: [],
        terminal_action: nil
      }
    end

    def follow_up_messages(first_response, tool_execution)
      [
        *follow_up_context_messages(tool_execution),
        {
          role: 'assistant',
          content: first_response[:assistant_text],
          tool_calls: first_response[:tool_calls].map do |tool_call|
            {
              id: tool_call[:id],
              type: tool_call[:type],
              function: {
                name: tool_call[:name],
                arguments: tool_call[:arguments]
              }
            }
          end
        },
        {
          role: 'tool',
          tool_call_id: first_response[:tool_calls].first[:id],
          content: tool_execution.tool_result.to_json
        }
      ]
    end

    def follow_up_context_messages(tool_execution)
      return normalized_messages unless order_lookup_tool_execution?(tool_execution)

      normalized_messages.map do |message|
        message.merge(content: AiAgents::PrivacyRedactor.redact_text(message[:content]))
      end
    end

    def order_lookup_tool_execution?(tool_execution)
      tool_execution.tool_event['tool'] == AiAgents::Config::IKAS_LOOKUP_ORDER_TOOL
    end

    def build_assistant_message(content:, tool_events:, terminal_action: nil, tool_result: nil)
      {
        'id' => SecureRandom.uuid,
        'role' => 'assistant',
        'content' => content.to_s,
        'created_at' => Time.current.iso8601(3),
        'tool_events' => Array(tool_events).map { |event| event.deep_stringify_keys },
        'terminal_action' => terminal_action,
        'tool_result' => tool_result&.deep_stringify_keys
      }.compact
    end

    def fallback_assistant_message
      'I could not complete that tool action safely. Please hand off to a human agent.'
    end
  end
end
