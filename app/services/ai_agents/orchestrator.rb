# frozen_string_literal: true

require 'bigdecimal'
require 'set'
require 'uri'

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
    INCOMPLETE_RESPONSE_RETRY_PROMPT = [
      'The previous AI response was cut off by the output limit.',
      'Reply again with one concise, complete customer-facing response.',
      'Preserve the latest customer constraints and use the available conversation and tool results as context.',
      'If tools remain necessary, call only the necessary enabled tools.'
    ].join(' ').freeze
    TOOL_BUDGET_EXHAUSTED_PROMPT = [
      'No more tools are available for this customer message.',
      'Reply to the customer without calling tools.',
      'Use the collected tool results as context; if the available information is insufficient, ask one focused clarification question.',
      'Do not mention tools, tool calls, budgets, internal searches, system limitations, or application safety checks.'
    ].join(' ').freeze
    PRESENT_OPTIONS_FALLBACK_PROMPT = [
      'The requested interactive options could not be presented safely.',
      'Ask the same focused question as plain customer-facing text using the available conversation and tool results as context.',
      'Do not call tools, invent options, mention internal errors, or promise a human handoff.'
    ].join(' ').freeze
    CUSTOMER_FACING_FINALIZER_PROMPT = [
      'Write the final customer-facing reply from the latest customer message and the available structured tool result messages.',
      'Use returned catalog entries for product names, prices, links, identifiers, and other concrete catalog fields instead of inventing entries. You may add normal reasoning and recommendations.',
      'The latest customer message controls the product/category scope of the final answer.',
      'Use previous conversation context only to resolve an ambiguous follow-up; if the latest customer message names a different product or category, answer only that new topic unless the customer explicitly asks to compare or combine topics.',
      'If tool results contain multiple query results, answer only the query or queries directly requested by the latest customer message; ignore previous-topic query results unless the customer explicitly asked to compare or combine topics.',
      'For no_match results without candidates, do not list store categories, previous products, or examples unless the tool returned them or the customer asked for alternatives.',
      'Write in natural support prose. Avoid robotic field-label blocks such as product/stock/color/price lines unless the customer explicitly asks for a structured table.',
      'Use returned stock fields when making concrete availability statements.',
      'Speak as the brand support assistant, not as software explaining how it worked.',
      'For unusual, unavailable, or unrealistic requests, stay neutral and professional; do not comment on the customer intent.',
      'If the exact requested item is unavailable, say that simply, then offer returned relevant alternatives or ask one focused customer question.',
      'Do not promise that a teammate will join, that the issue was escalated, or that someone was notified unless the current turn already completed handoff.',
      'Return only the message that should be sent to the customer.'
    ].join(' ').freeze
    CUSTOMER_FACING_FINALIZER_RETRY_PROMPT = [
      'The previous final customer-facing response attempted to call a tool, contained tool-call markup, or exposed internal process details.',
      'Write only the customer message now from the available conversation and tool results.',
      'Use returned catalog entries for product names, prices, links, identifiers, and other concrete catalog fields instead of inventing entries. You may add normal reasoning and recommendations.',
      'If the exact requested item is unavailable, say that simply and ask one focused customer question when needed.'
    ].join(' ').freeze
    MAX_TOOL_ITERATIONS = 4
    MAX_TOOL_CALLS_PER_RESPONSE = 4
    MAX_UNKNOWN_TOOL_CORRECTION_ATTEMPTS = 1
    INCOMPLETE_FINAL_RETRY_MAX_TOKENS = 4_096
    MAX_CATALOG_SEARCH_QUERY_UNITS = 3
    MAX_KNOWLEDGE_SEARCH_CALLS = 2
    MAX_ORDER_LOOKUP_CALLS = 1
    MAX_HUMAN_HANDOFF_CALLS = 1
    def initialize(ai_agent:, messages:, mode:, conversation: nil, trigger_message: nil, adapter: nil, prompt_override: nil, config_override: nil,
                   knowledge_sources_override: nil, improvement_operation: nil, initiated_by: nil)
      @ai_agent = ai_agent
      @messages = messages
      @mode = mode
      @conversation = conversation
      @trigger_message = trigger_message
      @runtime_config = config_override || (mode.to_s == 'live' ? ai_agent.live_config : ai_agent.config)
      @prompt_override = if mode.to_s == 'live' && prompt_override.nil?
                           ai_agent.live_prompt
                         else
                           prompt_override
                         end
      @runtime_knowledge_sources = resolve_knowledge_sources(knowledge_sources_override)
      @improvement_operation = improvement_operation || ('text_test' if mode.to_s == 'test')
      @initiated_by = initiated_by
      @config = AiAgents::Config.new(@runtime_config, allow_legacy_human_handoff_settings: true)
      @adapter = adapter || default_adapter
      @executed_tool_keys = Set.new
      @executed_tool_counts = Hash.new(0)
      @catalog_search_queries_truncated = 0
      @unknown_tool_correction_attempts = 0
    end

    def perform
      return failure_result unless ai_agent.enabled? || mode.to_s == 'test'
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

        tool_calls, rejection_code = bounded_tool_calls(response[:tool_calls])
        return rejected_tool_request_result(request_messages, tool_events, rejection_code) if rejection_code

        tool_executions = tool_calls.map { |tool_call| execute_tool_call(tool_call, tool_events) }
        tool_events.concat(tool_executions.map(&:tool_event))

        terminal_execution = tool_executions.find { |tool_execution| tool_execution.tool_result[:terminal_action].present? }
        return terminal_result(response, terminal_execution, tool_events: tool_events) if terminal_execution
        if correctable_unknown_tool_failure?(tool_executions, iteration)
          @unknown_tool_correction_attempts += 1
          request_messages = unknown_tool_correction_context(request_messages, tool_calls, tool_executions)
          next
        end
        if tool_failure?(tool_executions)
          return recoverable_tool_failure_result(request_messages, tool_calls, tool_executions, tool_events) if recoverable_tool_failure?(tool_executions)

          return safety_handoff_result(reason: tool_failure_reason(tool_executions), tool_events: tool_events)
        end

        request_messages = [
          *follow_up_context_messages(request_messages, tool_executions),
          assistant_tool_call_message(tool_calls),
          *tool_result_messages(tool_executions)
        ]
      end

      final_answer_result(request_messages, tool_events, TOOL_BUDGET_EXHAUSTED_PROMPT, budget_exhausted: true)
    rescue AiImprovements::Usage::Exhausted
      raise
    rescue StandardError => e
      Rails.logger.error("[AiAgents::Orchestrator] #{e.class}: #{e.message}")
      failure_result
    end

    private

    attr_reader :ai_agent, :messages, :mode, :conversation, :trigger_message, :adapter, :config, :executed_tool_keys,
                :executed_tool_counts, :catalog_search_queries_truncated, :prompt_override, :runtime_config, :runtime_knowledge_sources,
                :improvement_operation, :initiated_by

    def resolve_knowledge_sources(override)
      sources = if !override.nil?
                  override
                elsif mode.to_s == 'test'
                  AiKnowledgeSources::Snapshot.for(ai_agent)
                else
                  []
                end
      Array(sources).map { |source| source.to_h.deep_stringify_keys }.deep_dup
    end

    def default_adapter
      AiAgents::LlmAdapters::OpenAiCompatibleAdapter.new(
        ai_agent: ai_agent,
        account: ai_agent.account,
        prompt_override: prompt_override,
        config_override: runtime_config,
        knowledge_sources_override: runtime_knowledge_sources,
        improvement_operation: improvement_operation,
        initiated_by: initiated_by,
        llm_options: { system_prompt: effective_system_prompt }
      )
    end

    def tool_executor(tool_events)
      @tool_executor ||= AiAgents::ToolExecutor.new(
        ai_agent: ai_agent,
        account: ai_agent.account,
        mode: mode,
        executed_tool_keys: executed_tool_keys,
        context: {
          conversation: conversation,
          trigger_message: trigger_message,
          config: runtime_config,
          knowledge_sources: runtime_knowledge_sources,
          tool_events: tool_events
        }
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
      @llm_tools ||= runtime_tool_keys.filter_map do |tool_key|
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

    def runtime_tool_keys
      keys = config.enabled_tool_keys
      keys = [*keys, AiAgents::Config::KNOWLEDGE_SEARCH_TOOL] if runtime_knowledge_sources.present?
      keys -= [AiAgents::Config::PRESENT_OPTIONS_TOOL] unless AiAgents::ChannelCapabilities.present_options?(mode: mode, conversation: conversation)
      keys.uniq
    end

    def perform_llm_call(step:, request_messages:, tools: llm_tools, incomplete_retry_max_tokens: nil)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = adapter.perform(
        messages: request_messages,
        tools: tools,
        tool_choice: 'auto'
      )
      log_llm_call(step: step, request_messages: request_messages, request_tools: tools, status: 'succeeded', response: response,
                   duration_ms: duration_ms(started_at))
      if incomplete_llm_response?(response)
        return retry_incomplete_llm_call(
          step: step,
          request_messages: request_messages,
          tools: tools,
          max_tokens: incomplete_retry_max_tokens
        )
      end
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
      discard_incomplete_llm_response(response)
    rescue StandardError => e
      log_llm_call(step: "#{step}_retry", request_messages: retry_messages, request_tools: tools, status: 'failed', error: e,
                   duration_ms: duration_ms(started_at))
      raise
    end

    def retry_incomplete_llm_call(step:, request_messages:, tools:, max_tokens: nil)
      retry_messages = [*request_messages, { role: 'system', content: INCOMPLETE_RESPONSE_RETRY_PROMPT }]
      request_options = max_tokens.present? ? { max_tokens: max_tokens } : {}
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = adapter.perform(
        messages: retry_messages,
        tools: tools,
        tool_choice: 'auto',
        **request_options
      )
      log_llm_call(step: "#{step}_incomplete_retry", request_messages: retry_messages, request_tools: tools, status: 'succeeded', response: response,
                   request_options: request_options, duration_ms: duration_ms(started_at))
      discard_incomplete_llm_response(response)
    rescue StandardError => e
      log_llm_call(step: "#{step}_incomplete_retry", request_messages: retry_messages, request_tools: tools, status: 'failed', error: e,
                   request_options: request_options, duration_ms: duration_ms(started_at))
      raise
    end

    def empty_response_retry_prompt(tools)
      tools.present? ? EMPTY_RESPONSE_RETRY_PROMPT : EMPTY_FINAL_RESPONSE_RETRY_PROMPT
    end

    def empty_llm_response?(response)
      response[:assistant_text].blank? && response[:tool_calls].blank?
    end

    def incomplete_llm_response?(response)
      response[:finish_reason].to_s == 'length'
    end

    def discard_incomplete_llm_response(response)
      return response unless incomplete_llm_response?(response)

      response.merge(assistant_text: nil, tool_calls: [], incomplete_response: true)
    end

    def log_llm_call(step:, request_messages:, request_tools:, status:, response: {}, request_options: {}, error: nil, duration_ms: nil)
      llm_call_logger.call(
        step: step,
        model: ai_agent.account.ai_agent_model,
        request_messages: traced_request_messages(request_messages),
        request_tools: request_tools,
        request_options: request_options,
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
      @effective_system_prompt ||= AiAgents::PromptComposer.new(
        ai_agent: ai_agent,
        prompt_override: prompt_override,
        config_override: runtime_config,
        knowledge_sources_override: runtime_knowledge_sources,
        enabled_tool_keys_override: runtime_tool_keys
      ).effective_system_prompt
    end

    def duration_ms(started_at)
      return unless started_at

      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
    end

    def text_result(response, request_messages:, tool_events: [])
      return safety_handoff_result(reason: 'incomplete_llm_response', tool_events: tool_events) if response[:incomplete_response]
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
      terminal_action = tool_execution.tool_result[:terminal_action]
      telemetry_source = terminal_action == 'handoff' ? 'handoff' : 'tool_presentation'
      telemetry = turn_telemetry(tool_events: tool_events, final_answer_source: telemetry_source)
      assistant_message = build_assistant_message(
        content: tool_execution.tool_result[:customer_message] || response[:assistant_text] || fallback_assistant_message,
        tool_events: tool_events,
        terminal_action: terminal_action,
        tool_result: tool_execution.tool_result,
        telemetry: telemetry
      )
      attach_telemetry_to_latest_agent_message!(telemetry) if terminal_action == 'handoff'

      {
        assistant_message: assistant_message,
        tool_events: tool_events,
        terminal_action: terminal_action
      }
    end

    def final_answer_result(request_messages, tool_events, instruction, budget_exhausted: false)
      response = perform_llm_call(
        step: 'tool_final',
        request_messages: [*request_messages, { role: 'system', content: instruction }],
        tools: [],
        incomplete_retry_max_tokens: INCOMPLETE_FINAL_RETRY_MAX_TOKENS
      )
      if response[:incomplete_response]
        return incomplete_final_answer_result(request_messages, tool_events, budget_exhausted: budget_exhausted)
      end
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

    def incomplete_final_answer_result(request_messages, tool_events, budget_exhausted:)
      fallback = catalog_evidence_fallback_answer(tool_events, request_messages: request_messages)
      return safety_handoff_result(reason: 'incomplete_final_answer', tool_events: tool_events) if fallback.blank?

      {
        assistant_message: build_assistant_message(
          content: fallback,
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

      answer = if safe_customer_facing_answer?(answer)
                 answer
               else
                 finalize_customer_facing_answer(request_messages: request_messages, tool_events: tool_events)
               end
      sanitize_catalog_links(answer, tool_events)
    end

    def sanitize_catalog_links(answer, tool_events)
      sanitized = answer.to_s.strip.presence
      return sanitized if sanitized.blank?

      trusted_urls = catalog_link_urls(tool_events)
      return sanitized if trusted_urls.empty?

      sanitized = sanitized.gsub(/\]\((https?:\/\/[^\s)]*)\)/) do |markdown_link|
        raw_url = Regexp.last_match(1)
        normalized_url = normalize_catalog_url(raw_url)
        trusted_urls.include?(normalized_url) ? markdown_link.sub(raw_url, normalized_url) : markdown_link
      end

      trailing_link = sanitized.match(/\[[^\]\n]+\]\((?<url>https?:\/\/[^\s)]*)\z/)
      return sanitized unless trailing_link

      normalized_prefix = normalize_catalog_url(trailing_link[:url])
      matches = trusted_urls.select { |url| url.start_with?(normalized_prefix) }
      return sanitized unless matches.one? && catalog_url_prefix_identifies_product?(normalized_prefix, matches.first)

      "#{sanitized[0...trailing_link.begin(:url)]}#{matches.first})"
    end

    def catalog_url_prefix_identifies_product?(prefix, trusted_url)
      product_url = URI.parse(trusted_url)
      return false if product_url.path.blank? || product_url.path == '/'

      product_identity = trusted_url.split(/[?#]/, 2).first
      prefix.start_with?(product_identity)
    rescue URI::InvalidURIError
      false
    end

    def catalog_link_urls(tool_events)
      catalog_results(tool_events).flat_map { |result| catalog_link_urls_in(result) }.uniq
    end

    def catalog_results(tool_events)
      Array(tool_events).filter_map do |event|
        next unless event['tool'] == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL

        event['result'] || event[:result]
      end
    end

    def catalog_link_urls_in(value)
      case value
      when Hash
        value = value.deep_stringify_keys
        urls = []
        urls << normalize_catalog_url(value.dig('link', 'url')) if value.dig('link', 'url').present?
        urls.concat(value.each_value.flat_map { |child| catalog_link_urls_in(child) })
        urls
      when Array
        value.flat_map { |child| catalog_link_urls_in(child) }
      else
        []
      end
    end

    def normalize_catalog_url(url)
      URI::DEFAULT_PARSER.escape(url.to_s, /[" <>\\()]/)
    end

    def finalize_customer_facing_answer(request_messages:, tool_events:)
      finalizer_messages = [
        *request_messages,
        { role: 'system', content: CUSTOMER_FACING_FINALIZER_PROMPT }
      ]
      response = perform_llm_call(
        step: 'customer_facing_finalizer',
        request_messages: finalizer_messages,
        tools: [],
        incomplete_retry_max_tokens: INCOMPLETE_FINAL_RETRY_MAX_TOKENS
      )
      answer = response[:assistant_text].to_s.strip.presence
      return answer if answer && safe_customer_facing_answer?(answer)

      retry_response = perform_llm_call(
        step: 'customer_facing_finalizer_retry',
        request_messages: [
          *finalizer_messages,
          { role: 'system', content: CUSTOMER_FACING_FINALIZER_RETRY_PROMPT }
        ],
        tools: [],
        incomplete_retry_max_tokens: INCOMPLETE_FINAL_RETRY_MAX_TOKENS
      )
      retry_answer = retry_response[:assistant_text].to_s.strip.presence
      return retry_answer if retry_answer && safe_customer_facing_answer?(retry_answer)

      catalog_mixed_scope_fallback_answer(tool_events, request_messages: request_messages) ||
        catalog_evidence_fallback_answer(tool_events, request_messages: request_messages) ||
        catalog_clarification_fallback_answer(tool_events, request_messages: request_messages)
    end

    def safe_customer_facing_answer?(answer)
      !unsafe_customer_facing_answer?(answer)
    end

    def unsafe_customer_facing_answer?(answer)
      return true if answer.match?(/DSML|tool_calls|<\s*\/?\s*tool|<\s*\/?\s*function|invoke name=/i)

      answer.match?(internal_process_language_pattern)
    end

    def internal_process_language_pattern
      %r{
        \belimdeki\s+\d+\s+arama\s+sonucuna\s+göre\b |
        \b(?:based\s+on|according\s+to|from)\s+(?:the\s+)?(?:\d+\s+)?search\s+results?\b |
        \b(?:i|we)\s+(?:found|have)\s+\d+\s+search\s+results?\b
      }ix
    end

    def catalog_evidence_fallback_answer(tool_events, request_messages: [])
      groups = scoped_catalog_fallback_groups(catalog_fallback_candidate_groups(tool_events), request_messages)
      candidates = diverse_catalog_fallback_candidates(groups)
      return if candidates.empty?

      lines = candidates.map { |candidate| catalog_fallback_candidate_line(candidate) }
      price_note = catalog_fallback_price_note(candidates)
      "Şu ürün seçeneklerini buldum:\n\n#{lines.join("\n")}#{price_note}\n\nHangisini daha ayrıntılı incelemek istersiniz?"
    end

    def catalog_mixed_scope_fallback_answer(tool_events, request_messages: [])
      candidate_groups = scoped_catalog_fallback_groups(catalog_fallback_candidate_groups(tool_events), request_messages)
      clarification_groups = scoped_catalog_fallback_groups(catalog_clarification_fallback_groups(tool_events), request_messages)
      requested_scopes = requested_catalog_clarification_scopes(clarification_groups, request_messages)
      return if requested_scopes.length < 2

      candidates = diverse_catalog_fallback_candidates(candidate_groups)
      return if candidates.empty?

      candidate_tokens = catalog_fallback_candidate_scope_tokens(candidates)
      covered_scopes, missing_scopes = requested_scopes.partition { |scope| scope[:tokens].intersect?(candidate_tokens) }
      return if covered_scopes.empty? || missing_scopes.empty?

      category_options = missing_scopes.filter_map { |scope| scope.dig(:group, :options)&.first }.uniq.first(2)
      selected_candidates = candidates.first(3 - category_options.length)
      lines = selected_candidates.map { |candidate| catalog_fallback_candidate_line(candidate) }
      lines.concat(category_options.map { |option| "- Kategori: #{option}" })
      price_note = catalog_fallback_price_note(selected_candidates)

      "Şu seçenekleri buldum:\n\n#{lines.join("\n")}#{price_note}\n\nHangisini daha ayrıntılı incelemek istersiniz?"
    end

    def requested_catalog_clarification_scopes(groups, request_messages)
      latest_tokens = Set.new(catalog_scope_tokens(latest_customer_message(request_messages)))
      query_token_sets = groups.map { |group| Set.new(catalog_scope_tokens(group[:query])) }
      common_tokens = query_token_sets.reduce { |common, tokens| common & tokens } || Set.new

      groups.zip(query_token_sets).filter_map do |group, query_tokens|
        distinguishing_tokens = query_tokens - common_tokens
        next if distinguishing_tokens.empty? || !distinguishing_tokens.intersect?(latest_tokens)

        { group: group, tokens: distinguishing_tokens }
      end
    end

    def catalog_fallback_candidate_scope_tokens(candidates)
      Set.new(candidates.flat_map do |candidate|
        catalog_scope_tokens([candidate['display_name'], *Array(candidate['category_paths'])].join(' '))
      end)
    end

    def catalog_fallback_price_note(candidates)
      return '' unless candidates.any? { |candidate| catalog_fallback_reference_price(candidate).present? }

      "\n\nListelenen referans tutarlar nihai fiyat değildir; ölçü ve seçeneklere göre değişir."
    end

    def catalog_clarification_fallback_answer(tool_events, request_messages: [])
      groups = scoped_catalog_fallback_groups(catalog_clarification_fallback_groups(tool_events), request_messages)
      options = diverse_catalog_clarification_options(groups)
      return if options.empty?

      "Şu kategori seçenekleri eşleşiyor: #{options.join(', ')}. Hangisini incelemek istersiniz?"
    end

    def catalog_clarification_fallback_groups(tool_events)
      catalog_results(tool_events).flat_map do |result|
        result = result.to_h.deep_stringify_keys
        query_results = Array(result['queries']).select { |query_result| query_result.is_a?(Hash) }
        query_results = [result] if query_results.empty?

        query_results.filter_map do |query_result|
          query_result = query_result.deep_stringify_keys
          next unless query_result['result_type'] == 'clarify_category'

          options = Array(query_result['buckets']).filter_map do |bucket|
            next unless bucket.is_a?(Hash)

            bucket.deep_stringify_keys['label'].to_s.squish.presence
          end.uniq
          next if options.empty?

          { query: query_result['query'].to_s, options: options }
        end
      end
    end

    def diverse_catalog_clarification_options(groups)
      option_groups = groups.pluck(:options).reject(&:empty?)
      return [] if option_groups.empty?
      return option_groups.first.first(3) if option_groups.one?

      option_groups.filter_map(&:first).uniq.first(3)
    end

    def catalog_fallback_candidate_groups(tool_events)
      catalog_results(tool_events).flat_map do |result|
        result = result.to_h.deep_stringify_keys
        query_results = Array(result['queries']).select { |query_result| query_result.is_a?(Hash) }
        query_results = [result] if query_results.empty?
        query_results.map do |query_result|
          query_result = query_result.deep_stringify_keys
          {
            query: query_result['query'].to_s,
            candidates: Array(query_result['candidates']).filter_map do |candidate|
              candidate.deep_stringify_keys if candidate.is_a?(Hash)
            end
          }
        end
      end
    end

    def scoped_catalog_fallback_groups(groups, request_messages)
      return groups if groups.length < 2

      latest_tokens = Set.new(catalog_scope_tokens(latest_customer_message(request_messages)))
      return groups if latest_tokens.empty?

      query_token_sets = groups.map { |group| Set.new(catalog_scope_tokens(group[:query])) }
      common_tokens = query_token_sets.reduce { |common, tokens| common & tokens } || Set.new
      scoped_groups = groups.zip(query_token_sets).filter_map do |group, query_tokens|
        group if (query_tokens - common_tokens).intersect?(latest_tokens)
      end
      scoped_groups.presence || groups
    end

    def latest_customer_message(request_messages)
      message = Array(request_messages).reverse.find { |entry| (entry[:role] || entry['role']).to_s == 'user' }
      message&.[](:content) || message&.[]('content')
    end

    def catalog_scope_tokens(text)
      I18n.transliterate(text.to_s).downcase.scan(/[a-z0-9]+/)
    end

    def diverse_catalog_fallback_candidates(groups)
      candidate_groups = groups.map do |group|
        group[:candidates].select { |candidate| usable_catalog_fallback_candidate?(candidate) }
      end.reject(&:empty?)
      return [] if candidate_groups.empty?

      max_group_size = candidate_groups.map(&:size).max
      round_robin = max_group_size.times.flat_map do |index|
        candidate_groups.filter_map { |candidates| candidates[index] }
      end

      round_robin.uniq { |candidate| catalog_fallback_candidate_identity(candidate) }.first(3)
    end

    def catalog_fallback_candidate_identity(candidate)
      candidate.values_at('item_id', 'variant_id', 'display_name').compact.join(':').presence || candidate.dig('link', 'url').to_s
    end

    def usable_catalog_fallback_candidate?(candidate)
      return false if candidate['display_name'].to_s.strip.blank?

      stock = candidate['stock'].to_h.deep_stringify_keys
      stock.values_at('available', 'in_stock', 'sellable').none?(false)
    end

    def catalog_fallback_candidate_line(candidate)
      details = [candidate['display_name'].to_s.squish]
      reference_price = catalog_fallback_reference_price(candidate)
      details << reference_price if reference_price
      link = catalog_fallback_link(candidate)
      details << "[Ürünü inceleyin](#{link})" if link
      "- #{details.join(' — ')}"
    end

    def catalog_fallback_reference_price(candidate)
      price = candidate['price'].to_h.deep_stringify_keys
      return unless price['final_total_known'] == false

      amount = decimal_reference_amount(price['reference_amount'])
      currency = price['currency'].to_s.strip
      return if amount.nil? || !currency.match?(/\A[A-Z]{3}\z/)

      number = amount.to_s('F').sub(/\.0+\z/, '').sub(/(\.\d*?)0+\z/, '\\1')
      "listelenen referans tutar: #{number} #{currency}"
    end

    def catalog_fallback_link(candidate)
      url = candidate.dig('link', 'url').to_s.strip
      return unless url.match?(/\Ahttps?:\/\//i)

      normalize_catalog_url(url)
    end

    def decimal_reference_amount(value)
      return if value.blank?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
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
      handoff_call = tool_calls.find { |tool_call| tool_key_for(tool_call) == AiAgents::Config::HUMAN_HANDOFF_TOOL }
      return [handoff_call] if handoff_call

      present_options_call = tool_calls.find { |tool_call| tool_key_for(tool_call) == AiAgents::Config::PRESENT_OPTIONS_TOOL }
      if present_options_call
        evidence_calls = tool_calls.reject { |tool_call| tool_call.equal?(present_options_call) }
        return evidence_calls if evidence_calls.present?

        return [present_options_call]
      end

      terminal_tool_call = tool_calls.find { |tool_call| AiAgents::ToolRegistry.find(tool_call[:name])&.terminal }
      return [terminal_tool_call] if terminal_tool_call

      tool_calls
    end

    def bounded_tool_calls(tool_calls)
      selected_calls = tool_calls_to_execute(tool_calls)
      return [selected_calls, 'too_many_tool_calls'] if selected_calls.size > MAX_TOOL_CALLS_PER_RESPONSE

      fitted_calls = fit_catalog_search_calls_to_remaining_budget(selected_calls)
      [fitted_calls, tool_request_rejection_code(fitted_calls)]
    end

    def tool_request_rejection_code(tool_calls)
      return 'too_many_tool_calls' if tool_calls.size > MAX_TOOL_CALLS_PER_RESPONSE

      return 'tool_budget_exhausted' if tool_budget_exhausted?(tool_calls)

      nil
    end

    def fit_catalog_search_calls_to_remaining_budget(tool_calls)
      remaining_units = remaining_tool_budget(AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL)
      return tool_calls unless remaining_units.positive?

      requested_units = tool_calls.sum do |tool_call|
        tool_key_for(tool_call) == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL ? tool_call_budget_cost(tool_call) : 0
      end
      return tool_calls if requested_units <= remaining_units

      tool_calls.filter_map do |tool_call|
        next tool_call unless tool_key_for(tool_call) == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL

        requested_call_units = tool_call_budget_cost(tool_call)
        if requested_call_units <= remaining_units
          remaining_units -= requested_call_units
          next tool_call
        end

        retained_call = catalog_search_tool_call_with_query_limit(tool_call, remaining_units)
        retained_units = retained_call ? tool_call_budget_cost(retained_call) : 0
        @catalog_search_queries_truncated += requested_call_units - retained_units
        remaining_units -= retained_units
        retained_call
      end
    end

    def catalog_search_tool_call_with_query_limit(tool_call, query_limit)
      return unless query_limit.positive?

      args = parsed_tool_arguments(tool_call)
      queries = Array(args['queries']).filter_map { |query| query.to_s.strip.presence }.uniq.first(MAX_CATALOG_SEARCH_QUERY_UNITS)
      return tool_call if queries.empty?

      args['queries'] = queries.first(query_limit)
      args.delete('query')
      tool_call.merge(arguments: args.to_json)
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

    def execute_tool_call(tool_call, tool_events)
      tool_execution = tool_executor(tool_events).execute(tool_call)
      if AiAgents::ToolRegistry.find(tool_call[:name])
        executed_tool_counts[tool_key_for(tool_call)] += tool_call_budget_cost(tool_call)
      end
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
      when AiAgents::Config::KNOWLEDGE_SEARCH_TOOL then MAX_KNOWLEDGE_SEARCH_CALLS
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

    def recoverable_tool_failure?(tool_executions)
      failed = tool_executions.reject { |tool_execution| tool_execution.status.to_s == 'executed' }
      failed.present? && failed.all? { |tool_execution| tool_execution.tool_result[:recoverable] == true }
    end

    def recoverable_tool_failure_result(request_messages, tool_calls, tool_executions, tool_events)
      messages = [
        *follow_up_context_messages(request_messages, tool_executions),
        assistant_tool_call_message(tool_calls),
        *tool_result_messages(tool_executions)
      ]
      final_answer_result(messages, tool_events, PRESENT_OPTIONS_FALLBACK_PROMPT)
    end

    def correctable_unknown_tool_failure?(tool_executions, iteration)
      return false unless @unknown_tool_correction_attempts < MAX_UNKNOWN_TOOL_CORRECTION_ATTEMPTS
      return false unless iteration < MAX_TOOL_ITERATIONS - 1
      return false unless tool_executions.one?
      return false if available_tool_names.empty?

      execution = tool_executions.first
      execution.status.to_s != 'executed' && tool_failure_reason(tool_executions) == 'unknown_tool'
    end

    def unknown_tool_correction_context(request_messages, tool_calls, tool_executions)
      [
        *follow_up_context_messages(request_messages, tool_executions),
        assistant_tool_call_message(tool_calls),
        *unknown_tool_correction_messages(tool_executions)
      ]
    end

    def unknown_tool_correction_messages(tool_executions)
      tool_executions.map do |tool_execution|
        feedback = tool_execution.tool_result.merge(
          recoverable: true,
          requested_tool_name: tool_execution.tool_event['tool'],
          available_tool_names: available_tool_names,
          correction_instruction: 'Call at most one tool again using one exact available_tool_names value. Do not guess or alter a tool name.'
        )
        {
          role: 'tool',
          tool_call_id: tool_execution.tool_event['tool_call_id'],
          content: feedback.to_json
        }
      end
    end

    def available_tool_names
      llm_tools_for_remaining_budget.filter_map do |tool|
        tool.dig(:function, :name) || tool.dig('function', 'name')
      end
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

    def assistant_tool_call_message(tool_calls)
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
        'source_attributions' => source_attributions(tool_events).presence,
        'turn_telemetry' => (telemetry || turn_telemetry(tool_events: tool_events)),
        'terminal_action' => terminal_action,
        'tool_result' => tool_result&.deep_stringify_keys
      }.compact
    end

    def source_attributions(tool_events)
      attributions = Array(tool_events).flat_map do |event|
        next [] unless event['tool'] == AiAgents::Config::KNOWLEDGE_SEARCH_TOOL
        next [] unless event['status'].to_s == 'ok'

        Array(event.dig('result', 'attributions'))
      end
      attributions.uniq { |source| [source['source_id'], source['source_name']] }
    end

    def turn_telemetry(tool_events:, budget_exhausted: false, final_answer_source: nil)
      {
        'catalog_search_units_used' => executed_tool_counts[AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL],
        'catalog_search_queries_truncated' => catalog_search_queries_truncated,
        'knowledge_searches_used' => executed_tool_counts[AiAgents::Config::KNOWLEDGE_SEARCH_TOOL],
        'knowledge_sources_used' => source_attributions(tool_events).length,
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
      return 'knowledge_evidence' if tool_events.any? { |event| event['tool'] == AiAgents::Config::KNOWLEDGE_SEARCH_TOOL }

      'tool_context'
    end

    def fallback_assistant_message
      safety_handoff_message
    end
  end
end
