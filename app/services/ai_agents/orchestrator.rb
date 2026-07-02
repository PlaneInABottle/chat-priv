# frozen_string_literal: true

require 'set'

module AiAgents
  class Orchestrator
    EMPTY_RESPONSE_RETRY_PROMPT = [
      'The previous AI response was empty.',
      'Reply to the latest customer message.',
      'If tools are available and the answer requires them, call only the necessary enabled tool calls.'
    ].join(' ').freeze
    EMPTY_FINAL_RESPONSE_RETRY_PROMPT = [
      'The previous AI response was empty.',
      'Reply to the latest customer message from the available conversation and tool results.',
      'Do not call tools.'
    ].join(' ').freeze
    TOOL_BUDGET_EXHAUSTED_PROMPT = [
      'No more tools are available for this customer message.',
      'Reply to the customer without calling tools.',
      'Use the collected product/order evidence only; if it is insufficient, ask one focused clarification question.',
      'Do not mention tools, tool calls, budgets, internal searches, system limitations, or application safety checks.'
    ].join(' ').freeze
    CUSTOMER_FACING_FINALIZER_PROMPT = [
      'Write the final customer-facing reply from the latest customer message and the available structured tool result messages.',
      'Use only concrete facts, product names, prices, links, order fields, and compatibility details present in those results.',
      'Use price.amount only when price.final_total_known is not false. If only reference pricing is present, say final price depends on selected options or dimensions instead of quoting a final total.',
      'Speak as the brand support assistant, not as software explaining how it worked.',
      'For unusual, unavailable, or unrealistic requests, stay neutral and professional; do not comment on the customer intent.',
      'If the exact requested item is unavailable, say that simply, then offer returned relevant alternatives or ask one focused customer question.',
      'Do not promise that a teammate will join, that the issue was escalated, or that someone was notified unless the current turn already completed handoff.',
      'Return only the message that should be sent to the customer.'
    ].join(' ').freeze
    CUSTOMER_FACING_FINALIZER_RETRY_PROMPT = [
      'The previous final customer-facing response attempted to call a tool, but this final step cannot use tools.',
      'Write only the customer message now from the already available evidence.',
      'If the exact requested item is unavailable, say that simply and ask one focused customer question when needed.'
    ].join(' ').freeze
    MAX_TOOL_ITERATIONS = 4
    MAX_TOOL_CALLS_PER_RESPONSE = 4
    MAX_CATALOG_SEARCH_QUERY_UNITS = 3
    MAX_ORDER_LOOKUP_CALLS = 1
    MAX_HUMAN_HANDOFF_CALLS = 1

    def initialize(ai_agent:, messages:, mode:, conversation: nil, trigger_message: nil, adapter: nil)
      @ai_agent = ai_agent
      @messages = messages
      @mode = mode
      @conversation = conversation
      @trigger_message = trigger_message
      @adapter = adapter || default_adapter
      @config = AiAgents::Config.new(ai_agent.config, allow_legacy_human_handoff_settings: true)
      @executed_tool_keys = Set.new
      @executed_tool_counts = Hash.new(0)
    end

    def perform
      return failure_result unless ai_agent.enabled?
      return failure_result unless ai_agent.account.ai_agent_enabled?
      return failure_result unless config.valid?

      request_messages = normalized_messages
      tool_events = []

      MAX_TOOL_ITERATIONS.times do |iteration|
        response = perform_llm_call(
          step: llm_step_name(iteration),
          request_messages: request_messages,
          tools: llm_tools_for_remaining_budget
        )

        return text_result(response, request_messages: request_messages, tool_events: tool_events) if response[:tool_calls].blank?

        tool_calls = tool_calls_to_execute(response[:tool_calls])
        rejection_code = tool_request_rejection_code(tool_calls)
        return rejected_tool_request_result(request_messages, tool_events, rejection_code) if rejection_code

        tool_executions = tool_calls.map { |tool_call| execute_tool_call(tool_call) }
        tool_events.concat(tool_executions.map(&:tool_event))

        terminal_execution = tool_executions.find { |tool_execution| tool_execution.tool_result[:terminal_action].present? }
        return terminal_result(response, terminal_execution, tool_events: tool_events) if terminal_execution
        return safety_handoff_result(reason: tool_failure_reason(tool_executions), tool_events: tool_events) if tool_failure?(tool_executions)

        request_messages = [
          *follow_up_context_messages(request_messages, tool_executions),
          assistant_tool_call_message(response, tool_calls),
          *tool_result_messages(tool_executions)
        ]
      end

      final_answer_result(request_messages, tool_events, TOOL_BUDGET_EXHAUSTED_PROMPT, budget_exhausted: true)
    rescue StandardError => e
      Rails.logger.error("[AiAgents::Orchestrator] #{e.class}: #{e.message}")
      failure_result
    end

    private

    attr_reader :ai_agent, :messages, :mode, :conversation, :trigger_message, :adapter, :config, :executed_tool_keys, :executed_tool_counts

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

    def perform_llm_call(step:, request_messages:, tools: llm_tools)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = adapter.perform(
        messages: request_messages,
        tools: tools,
        tool_choice: 'auto'
      )
      log_llm_call(step: step, request_messages: request_messages, request_tools: tools, status: 'succeeded', response: response,
                   duration_ms: duration_ms(started_at))
      return retry_empty_llm_call(step: step, request_messages: request_messages, tools: tools) if empty_llm_response?(response)

      response
    rescue StandardError => e
      log_llm_call(step: step, request_messages: request_messages, request_tools: tools, status: 'failed', error: e,
                   duration_ms: duration_ms(started_at))
      raise
    end

    def retry_empty_llm_call(step:, request_messages:, tools:)
      retry_messages = [*request_messages, { role: 'system', content: empty_response_retry_prompt(tools) }]
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = adapter.perform(
        messages: retry_messages,
        tools: tools,
        tool_choice: 'auto'
      )
      log_llm_call(step: "#{step}_retry", request_messages: retry_messages, request_tools: tools, status: 'succeeded', response: response,
                   duration_ms: duration_ms(started_at))
      response
    rescue StandardError => e
      log_llm_call(step: "#{step}_retry", request_messages: retry_messages, request_tools: tools, status: 'failed', error: e,
                   duration_ms: duration_ms(started_at))
      raise
    end

    def empty_response_retry_prompt(tools)
      tools.present? ? EMPTY_RESPONSE_RETRY_PROMPT : EMPTY_FINAL_RESPONSE_RETRY_PROMPT
    end

    def empty_llm_response?(response)
      response[:assistant_text].blank? && response[:tool_calls].blank?
    end

    def log_llm_call(step:, request_messages:, request_tools:, status:, response: {}, error: nil, duration_ms: nil)
      llm_call_logger.call(
        step: step,
        model: ai_agent.account.ai_agent_model,
        request_messages: traced_request_messages(request_messages),
        request_tools: request_tools,
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

    def text_result(response, request_messages:, tool_events: [])
      return failure_result if response[:assistant_text].blank?
      public_answer = customer_facing_answer(response[:assistant_text], request_messages: request_messages, tool_events: tool_events)
      return safety_handoff_result(reason: 'empty_customer_facing_answer', tool_events: tool_events) if public_answer.blank?

      {
        assistant_message: build_assistant_message(content: public_answer, tool_events: tool_events),
        tool_events: tool_events,
        terminal_action: nil
      }
    end

    def terminal_result(response, tool_execution, tool_events:)
      telemetry = turn_telemetry(tool_events: tool_events, final_answer_source: 'handoff')
      assistant_message = build_assistant_message(
        content: tool_execution.tool_result[:customer_message] || response[:assistant_text] || fallback_assistant_message,
        tool_events: tool_events,
        terminal_action: tool_execution.tool_result[:terminal_action],
        tool_result: tool_execution.tool_result,
        telemetry: telemetry
      )
      attach_telemetry_to_latest_agent_message!(telemetry) if tool_execution.tool_result[:terminal_action] == 'handoff'

      {
        assistant_message: assistant_message,
        tool_events: tool_events,
        terminal_action: tool_execution.tool_result[:terminal_action]
      }
    end

    def final_answer_result(request_messages, tool_events, instruction, budget_exhausted: false)
      response = perform_llm_call(
        step: 'tool_final',
        request_messages: [*request_messages, { role: 'system', content: instruction }],
        tools: []
      )
      return safety_handoff_result(reason: 'empty_final_answer', tool_events: tool_events) if response[:assistant_text].blank?
      public_answer = customer_facing_answer(response[:assistant_text], request_messages: request_messages, tool_events: tool_events)
      return safety_handoff_result(reason: 'empty_customer_facing_answer', tool_events: tool_events) if public_answer.blank?

      {
        assistant_message: build_assistant_message(
          content: public_answer,
          tool_events: tool_events,
          telemetry: turn_telemetry(tool_events: tool_events, budget_exhausted: budget_exhausted)
        ),
        tool_events: tool_events,
        terminal_action: nil
      }
    end

    def customer_facing_answer(content, request_messages:, tool_events:)
      answer = content.to_s.strip
      return answer if tool_events.blank?

      finalize_customer_facing_answer(request_messages: request_messages)
    end

    def finalize_customer_facing_answer(request_messages:)
      finalizer_messages = [
        *request_messages,
        { role: 'system', content: CUSTOMER_FACING_FINALIZER_PROMPT }
      ]
      response = perform_llm_call(
        step: 'customer_facing_finalizer',
        request_messages: finalizer_messages,
        tools: []
      )
      answer = response[:assistant_text].to_s.strip.presence
      return answer if answer

      retry_response = perform_llm_call(
        step: 'customer_facing_finalizer_retry',
        request_messages: [
          *finalizer_messages,
          { role: 'system', content: CUSTOMER_FACING_FINALIZER_RETRY_PROMPT }
        ],
        tools: []
      )
      retry_response[:assistant_text].to_s.strip.presence
    end

    def failure_result
      {
        assistant_message: nil,
        tool_events: [],
        terminal_action: nil
      }
    end

    def llm_step_name(iteration)
      return 'initial' if iteration.zero?
      return 'tool_follow_up' if iteration == 1

      "tool_research_#{iteration}"
    end

    def llm_tools_for_remaining_budget
      llm_tools.select do |tool|
        remaining_tool_budget(tool.dig(:function, :name) || tool.dig('function', 'name')).positive?
      end
    end

    def tool_calls_to_execute(tool_calls)
      terminal_tool_call = tool_calls.find do |tool_call|
        AiAgents::ToolRegistry.find(tool_call[:name])&.terminal
      end
      return [terminal_tool_call] if terminal_tool_call

      tool_calls
    end

    def tool_request_rejection_code(tool_calls)
      return 'too_many_tool_calls' if tool_calls.size > MAX_TOOL_CALLS_PER_RESPONSE

      return 'tool_budget_exhausted' if tool_budget_exhausted?(tool_calls)

      nil
    end

    def rejected_tool_request_result(request_messages, tool_events, rejection_code)
      return final_answer_result(request_messages, tool_events, TOOL_BUDGET_EXHAUSTED_PROMPT, budget_exhausted: true) if rejection_code == 'tool_budget_exhausted' && tool_events.present?

      safety_handoff_result(reason: rejection_code, tool_events: tool_events)
    end

    def tool_budget_exhausted?(tool_calls)
      requested_counts = Hash.new(0)
      tool_calls.each do |tool_call|
        requested_counts[tool_key_for(tool_call)] += tool_call_budget_cost(tool_call)
      end
      requested_counts.any? { |tool_key, requested_count| requested_count > remaining_tool_budget(tool_key) }
    end

    def execute_tool_call(tool_call)
      tool_execution = tool_executor.execute(tool_call)
      executed_tool_counts[tool_key_for(tool_call)] += tool_call_budget_cost(tool_call)
      tool_execution
    end

    def tool_key_for(tool_call_or_name)
      name = tool_call_or_name.is_a?(Hash) ? tool_call_or_name[:name] : tool_call_or_name
      AiAgents::ToolRegistry.find(name)&.key || name.to_s
    end

    def remaining_tool_budget(tool_key_or_name)
      tool_key = tool_key_for(tool_key_or_name)
      max_tool_calls_for(tool_key) - executed_tool_counts[tool_key]
    end

    def max_tool_calls_for(tool_key)
      case tool_key.to_s
      when AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL then MAX_CATALOG_SEARCH_QUERY_UNITS
      when AiAgents::Config::IKAS_LOOKUP_ORDER_TOOL then MAX_ORDER_LOOKUP_CALLS
      when AiAgents::Config::HUMAN_HANDOFF_TOOL then MAX_HUMAN_HANDOFF_CALLS
      else 1
      end
    end

    def tool_call_budget_cost(tool_call)
      return catalog_search_query_units(tool_call) if tool_key_for(tool_call) == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL

      1
    end

    def catalog_search_query_units(tool_call)
      args = parsed_tool_arguments(tool_call)
      queries = Array(args['queries']).filter_map { |query| query.to_s.strip.presence }.uniq
      return queries.first(MAX_CATALOG_SEARCH_QUERY_UNITS).size if queries.any?

      1
    end

    def parsed_tool_arguments(tool_call)
      JSON.parse(tool_call[:arguments].presence || '{}')
    rescue JSON::ParserError
      {}
    end

    def tool_failure?(tool_executions)
      tool_executions.any? { |tool_execution| tool_execution.status.to_s != 'executed' }
    end

    def tool_failure_reason(tool_executions)
      failed_execution = tool_executions.find { |tool_execution| tool_execution.status.to_s != 'executed' }
      failed_execution&.tool_result&.[](:error_code) || failed_execution&.tool_result&.[]('error_code') || 'tool_execution_failed'
    end

    def follow_up_context_messages(request_messages, tool_executions)
      return request_messages unless tool_executions.any? { |tool_execution| order_lookup_tool_execution?(tool_execution) }

      request_messages.map do |message|
        message.merge(content: AiAgents::PrivacyRedactor.redact_text(message[:content]))
      end
    end

    def order_lookup_tool_execution?(tool_execution)
      tool_execution.tool_event['tool'] == AiAgents::Config::IKAS_LOOKUP_ORDER_TOOL
    end

    def assistant_tool_call_message(response, tool_calls)
      {
        role: 'assistant',
        content: nil,
        tool_calls: tool_calls.map do |tool_call|
          {
            id: tool_call[:id],
            type: tool_call[:type],
            function: {
              name: tool_call[:name],
              arguments: tool_call[:arguments]
            }
          }
        end
      }
    end

    def tool_result_messages(tool_executions)
      tool_executions.map do |tool_execution|
        {
          role: 'tool',
          tool_call_id: tool_execution.tool_event['tool_call_id'],
          content: tool_execution.tool_result.to_json
        }
      end
    end

    def safety_handoff_result(reason:, tool_events: [])
      executed_tool_counts[AiAgents::Config::HUMAN_HANDOFF_TOOL] += 1
      args = safety_handoff_arguments(reason)
      tool_call = {
        id: "safety_handoff_#{SecureRandom.hex(8)}",
        type: 'function',
        name: AiAgents::Config::HUMAN_HANDOFF_TOOL,
        arguments: args.to_json
      }
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      definition = AiAgents::ToolRegistry.find(AiAgents::Config::HUMAN_HANDOFF_TOOL)
      result = AiAgents::Tools::HumanHandoffService.new(
        ai_agent: ai_agent,
        account: ai_agent.account,
        mode: mode,
        settings: config.tool_settings(AiAgents::Config::HUMAN_HANDOFF_TOOL),
        conversation: conversation,
        trigger_message: trigger_message
      ).call(args: args)
      event = safety_handoff_tool_event(tool_call, definition, result)
      log_safety_handoff(tool_call, definition, result, args, started_at)
      all_tool_events = [*tool_events, event]
      telemetry = turn_telemetry(tool_events: all_tool_events, final_answer_source: 'handoff')
      attach_telemetry_to_latest_agent_message!(telemetry) if result[:terminal_action] == 'handoff'

      {
        assistant_message: build_assistant_message(
          content: result[:customer_message] || safety_handoff_message,
          tool_events: all_tool_events,
          terminal_action: result[:terminal_action],
          tool_result: result,
          telemetry: telemetry
        ),
        tool_events: all_tool_events,
        terminal_action: result[:terminal_action]
      }
    end

    def safety_handoff_arguments(reason)
      {
        'reason' => "AI agent automation stopped: #{reason}",
        'customer_message' => safety_handoff_message,
        'internal_note' => "AI agent automation stopped because #{reason}. Review the latest customer message and AI tool logs.",
        'labels' => ['human_handoff']
      }
    end

    def safety_handoff_message
      'Sizi bir temsilciye aktarıyorum. Ekibimiz yardımcı olacak.'
    end

    def safety_handoff_tool_event(tool_call, definition, result)
      {
        'tool' => definition.key,
        'status' => result[:status],
        'tool_call_id' => tool_call[:id],
        'terminal' => true,
        'args' => JSON.parse(tool_call[:arguments]),
        'result' => result.deep_stringify_keys
      }
    end

    def log_safety_handoff(tool_call, definition, result, args, started_at)
      AiAgents::ToolExecutionLogger.new(
        ai_agent: ai_agent,
        account: ai_agent.account,
        conversation: conversation,
        trigger_message: trigger_message,
        mode: mode
      ).call(
        tool_call: tool_call,
        definition: definition,
        status: result[:status] == 'ok' ? 'executed' : 'error',
        payload: {
          tool_result: result,
          args: args,
          duration_ms: duration_ms(started_at)
        }
      )
    rescue StandardError => e
      Rails.logger.error("[AiAgents::SafetyHandoffLogger] #{e.class}: #{e.message}")
    end

    def build_assistant_message(content:, tool_events:, terminal_action: nil, tool_result: nil, telemetry: nil)
      {
        'id' => SecureRandom.uuid,
        'role' => 'assistant',
        'content' => content.to_s,
        'created_at' => Time.current.iso8601(3),
        'tool_events' => Array(tool_events).map { |event| event.deep_stringify_keys },
        'turn_telemetry' => (telemetry || turn_telemetry(tool_events: tool_events)),
        'terminal_action' => terminal_action,
        'tool_result' => tool_result&.deep_stringify_keys
      }.compact
    end

    def turn_telemetry(tool_events:, budget_exhausted: false, final_answer_source: nil)
      {
        'catalog_search_units_used' => executed_tool_counts[AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL],
        'order_lookup_used' => executed_tool_counts[AiAgents::Config::IKAS_LOOKUP_ORDER_TOOL],
        'handoff_used' => handoff_used?(tool_events),
        'budget_exhausted' => budget_exhausted,
        'final_answer_source' => final_answer_source || final_answer_source_for(tool_events)
      }
    end

    def attach_telemetry_to_latest_agent_message!(telemetry)
      return unless mode.to_s == 'live'
      return unless conversation.is_a?(Conversation)

      message = conversation.reload.messages
                            .where(private: false, sender_type: 'AgentBot')
                            .where('id > ?', trigger_message&.id || 0)
                            .reorder(id: :desc)
                            .first
      return unless message

      content_attributes = message.content_attributes.is_a?(Hash) ? message.content_attributes.deep_stringify_keys : {}
      content_attributes['ai_agent'] = (content_attributes['ai_agent'] || {}).merge('turn_telemetry' => telemetry)
      message.update!(content_attributes: content_attributes)
    rescue StandardError => e
      Rails.logger.error("[AiAgents::TurnTelemetry] #{e.class}: #{e.message}")
    end

    def handoff_used?(tool_events)
      tool_events.any? do |event|
        event['tool'] == AiAgents::Config::HUMAN_HANDOFF_TOOL ||
          event.dig('result', 'terminal_action') == 'handoff' ||
          event.dig(:result, :terminal_action) == 'handoff'
      end
    end

    def final_answer_source_for(tool_events)
      return 'model_only' if tool_events.blank?
      return 'tool_error' if tool_events.any? { |event| event['status'].to_s == 'error' || event['status'].to_s == 'rejected' }

      'tool_evidence'
    end

    def fallback_assistant_message
      safety_handoff_message
    end
  end
end
