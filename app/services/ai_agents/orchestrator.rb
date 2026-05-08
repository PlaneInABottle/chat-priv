# frozen_string_literal: true

require 'set'

module AiAgents
  class Orchestrator
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
      return failure_result unless config.valid?

      first_response = adapter.perform(
        messages: normalized_messages,
        tools: llm_tools,
        tool_choice: 'auto'
      )

      return text_result(first_response) if first_response[:tool_calls].blank?
      return rejected_result('multiple_tool_calls') if first_response[:tool_calls].size > 1

      tool_execution = tool_executor.execute(first_response[:tool_calls].first)
      return rejected_tool_result(tool_execution.tool_event) if tool_execution.status == 'rejected'
      return terminal_result(first_response, tool_execution) if tool_execution.tool_result[:terminal_action].present?
      return tool_error_result(first_response, tool_execution) if tool_execution.status == 'error'

      follow_up_response = adapter.perform(
        messages: follow_up_messages(first_response, tool_execution),
        tools: llm_tools,
        tool_choice: 'auto'
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
      config.enabled_tool_keys.filter_map do |tool_key|
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
        *normalized_messages,
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
