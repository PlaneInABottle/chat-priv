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
      'Preserve the latest customer constraints and use only the available verified evidence.',
      'If tools remain necessary, call only the necessary enabled tools.'
    ].join(' ').freeze
    TOOL_BUDGET_EXHAUSTED_PROMPT = [
      'No more tools are available for this customer message.',
      'Reply to the customer without calling tools.',
      'Use only the collected tool evidence; if it is insufficient, ask one focused clarification question.',
      'Do not mention tools, tool calls, budgets, internal searches, system limitations, or application safety checks.'
    ].join(' ').freeze
    PRESENT_OPTIONS_FALLBACK_PROMPT = [
      'The requested interactive options could not be presented safely.',
      'Ask the same focused question as plain customer-facing text using only the available conversation and tool evidence.',
      'Do not call tools, invent options, mention internal errors, or promise a human handoff.'
    ].join(' ').freeze
    CUSTOMER_FACING_FINALIZER_PROMPT = [
      'Write the final customer-facing reply from the latest customer message and the available structured tool result messages.',
      'Use only concrete facts, policies, verified knowledge excerpts, product details, prices, links, and order fields present in those results.',
      'Material, durability, pet-resistance, damage, and suitability claims require explicit candidate evidence, attributes, features, or description supporting that exact type of claim. Product names and categories alone do not support physical performance or pet-behavior claims.',
      'The latest customer message controls the product/category scope of the final answer.',
      'Use previous conversation context only to resolve an ambiguous follow-up; if the latest customer message names a different product or category, answer only that new topic unless the customer explicitly asks to compare or combine topics.',
      'If tool results contain multiple query results, answer only the query or queries directly requested by the latest customer message; ignore previous-topic query results unless the customer explicitly asked to compare or combine topics.',
      'Use price.amount only when price.final_total_known is not false. If only reference pricing is present, say final price depends on selected options or dimensions instead of quoting a final total.',
      'For custom-option products with price.final_total_known false, do not repeat numeric reference prices even if the customer mentioned one. Refer to it as a listed or visible reference amount instead.',
      'For no_match results without candidates, do not list store categories, previous products, or examples unless the tool returned them or the customer asked for alternatives.',
      'Write in natural support prose. Avoid robotic field-label blocks such as product/stock/color/price lines unless the customer explicitly asks for a structured table.',
      'Use stock evidence to avoid recommending unavailable products. Do not mention that an item is in stock unless availability is the customer question or it changes the recommendation.',
      'Speak as the brand support assistant, not as software explaining how it worked.',
      'For unusual, unavailable, or unrealistic requests, stay neutral and professional; do not comment on the customer intent.',
      'If the exact requested item is unavailable, say that simply, then offer returned relevant alternatives or ask one focused customer question.',
      'Do not promise that a teammate will join, that the issue was escalated, or that someone was notified unless the current turn already completed handoff.',
      'Return only the message that should be sent to the customer.'
    ].join(' ').freeze
    CUSTOMER_FACING_FINALIZER_RETRY_PROMPT = [
      'The previous final customer-facing response attempted to call a tool, contained tool-call markup, or repeated a non-final reference price.',
      'Write only the customer message now from the already available evidence.',
      'Do not repeat numeric reference prices when price.final_total_known is false.',
      'Remove unsupported material, durability, pet-resistance, damage, and suitability claims while preserving verified product names, links, and properly qualified price comparisons.',
      'If the exact requested item is unavailable, say that simply and ask one focused customer question when needed.'
    ].join(' ').freeze
    MAX_TOOL_ITERATIONS = 4
    MAX_TOOL_CALLS_PER_RESPONSE = 4
    MAX_UNKNOWN_TOOL_CORRECTION_ATTEMPTS = 1
    MAX_CATALOG_SEARCH_QUERY_UNITS = 3
    MAX_KNOWLEDGE_SEARCH_CALLS = 2
    MAX_ORDER_LOOKUP_CALLS = 1
    MAX_HUMAN_HANDOFF_CALLS = 1
    CATALOG_PRICE_COMPARISON_PATTERN = %r{
      daha\s+(?:ucuz|ekonomik|pahalı|uygun\s+fiyatlı|düşük|yüksek) |
      \b(?:cheaper|more\s+(?:affordable|expensive)|less\s+expensive|lower|higher)(?:-priced)?\b
    }ix
    CATALOG_REFERENCE_PRICE_QUALIFIER_PATTERN = %r{
      \b(?:
        referans\s+(?:tutar|fiyat) | reference\s+(?:amount|price) |
        (?:listelenen|görünen)\s+(?:referans\s+)?(?:tutar|fiyat) |
        (?:listed|visible)\s+(?:reference\s+)?(?:amount|price)
      )
    }ix
    CATALOG_EVIDENCE_ONLY_CLAIM_PATTERNS = {
      material: %r{
        \b(?:
          (?:sert|rijit)\s+(?:çerçeve(?:li)?|kasa(?:lı)?)(?:dir)? |
          (?:rigid|hard)\s+frames? |
          (?:alüminyum|aluminyum|çelik|celik|metal|plastik|ahşap|ahsap|wood(?:en)?|steel|alumin(?:um|ium)|plastic)
          (?:dan|den)?\s+(?:yapılmış|yapilmis|çerçeve(?:li)?|kasa(?:lı)?|frame(?:d)?) |
          made\s+(?:of|from)\s+(?:wood|steel|alumin(?:um|ium)|metal|plastic)
        )\b
      }ix,
      durability: %r{
        \b(?:
          (?:daha\s+)?(?:sağlam|saglam|dayanıklı|dayanikli)(?:d[ıi]r)? |
          ezilmez | sark(?:abilir|ar|maz) | yırtıl(?:maz|abilir) | yirtil(?:maz|abilir) |
          kırıl(?:maz|abilir) | kiril(?:maz|abilir) | deforme\s+ol(?:maz|abilir) |
          durable | sturd(?:y|ier) | strong(?:er)? | (?:will|can|may|won't)\s+(?:sag|tear|bend|break)
        )\b
      }ix,
      pet_resistance: %r{
        \b(?:
          (?:kedi(?:niz|ler)?|köpek(?:iniz|ler)?|evcil\s+hayvan|cats?|dogs?|pets?).{0,50}
          (?:tırmala[[:alpha:]]*|tirmala[[:alpha:]]*|tırman[[:alpha:]]*|tirman[[:alpha:]]*|scratch\w*|claw\w*|climb\w*|resistan\w*|proof) |
          (?:tırmala[[:alpha:]]*|tirmala[[:alpha:]]*|scratch\w*|claw\w*|pet[_\s-]?proof).{0,50}
          (?:kedi[[:alpha:]]*|köpek[[:alpha:]]*|evcil\s+hayvan|cats?|dogs?|pets?)
        )\b
      }ix,
      damage: %r{
        \b(?:
          (?:hasar|zarar)\s+gör(?:ebilir|ür|ur|mez) |
          damage[_\s-]?resistan\w* | prone\s+to\s+damage |
          (?:can|may|will|won't)\s+(?:be\s+)?damag(?:e|ed)
        )\b
      }ix,
      suitability: %r{
        \b(?:
          en\s+uygun\s+(?:seçenek|secenek|ürün|urun|model) |
          ideal(?:dir)? |
          (?:kedi(?:niz|ler)?|köpek(?:iniz|ler)?|evcil\s+hayvan)\s+için\s+(?:en\s+)?uygun |
          best\s+(?:choice|option) | most\s+suitable |
          (?:suitable|recommended)[_\s-]*for.{0,20}(?:cats?|dogs?|pets?)
        )\b
      }ix
    }.freeze

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

        tool_calls = tool_calls_to_execute(response[:tool_calls])
        rejection_code = tool_request_rejection_code(tool_calls)
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
                :executed_tool_counts, :prompt_override, :runtime_config, :runtime_knowledge_sources, :improvement_operation, :initiated_by

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

    def perform_llm_call(step:, request_messages:, tools: llm_tools)
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = adapter.perform(
        messages: request_messages,
        tools: tools,
        tool_choice: 'auto'
      )
      log_llm_call(step: step, request_messages: request_messages, request_tools: tools, status: 'succeeded', response: response,
                   duration_ms: duration_ms(started_at))
      return retry_incomplete_llm_call(step: step, request_messages: request_messages, tools: tools) if incomplete_llm_response?(response)
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

    def retry_incomplete_llm_call(step:, request_messages:, tools:)
      retry_messages = [*request_messages, { role: 'system', content: INCOMPLETE_RESPONSE_RETRY_PROMPT }]
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = adapter.perform(
        messages: retry_messages,
        tools: tools,
        tool_choice: 'auto'
      )
      log_llm_call(step: "#{step}_incomplete_retry", request_messages: retry_messages, request_tools: tools, status: 'succeeded', response: response,
                   duration_ms: duration_ms(started_at))
      discard_incomplete_llm_response(response)
    rescue StandardError => e
      log_llm_call(step: "#{step}_incomplete_retry", request_messages: retry_messages, request_tools: tools, status: 'failed', error: e,
                   duration_ms: duration_ms(started_at))
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
        tools: []
      )
      return safety_handoff_result(reason: 'incomplete_final_answer', tool_events: tool_events) if response[:incomplete_response]
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

      answer = if single_catalog_no_match_without_candidates?(tool_events)
                 catalog_no_match_fallback_answer(tool_events)
               elsif safe_customer_facing_answer?(answer, tool_events)
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
        tools: []
      )
      answer = response[:assistant_text].to_s.strip.presence
      return answer if answer && safe_customer_facing_answer?(answer, tool_events)

      retry_response = perform_llm_call(
        step: 'customer_facing_finalizer_retry',
        request_messages: [
          *finalizer_messages,
          { role: 'system', content: CUSTOMER_FACING_FINALIZER_RETRY_PROMPT }
        ],
        tools: []
      )
      retry_answer = retry_response[:assistant_text].to_s.strip.presence
      sanitized_answer = sanitize_reference_prices(retry_answer, tool_events)
      return sanitized_answer if sanitized_answer && safe_customer_facing_answer?(sanitized_answer, tool_events)

      nil
    end

    def safe_customer_facing_answer?(answer, tool_events)
      !unsafe_customer_facing_answer?(answer) && !reference_price_leak?(answer, tool_events) &&
        !unsupported_catalog_claim?(answer, tool_events)
    end

    def unsupported_catalog_claim?(answer, tool_events)
      return false if catalog_results(tool_events).empty?

      unsupported_price_comparison = answer.match?(CATALOG_PRICE_COMPARISON_PATTERN) &&
                                     !catalog_price_comparison_supported?(answer, tool_events)
      unsupported_evidence_only_claim = CATALOG_EVIDENCE_ONLY_CLAIM_PATTERNS.values.any? do |pattern|
        answer.match?(pattern) && !catalog_claim_supported?(tool_events, pattern)
      end
      unsupported_price_comparison || unsupported_evidence_only_claim
    end

    def catalog_price_comparison_supported?(answer, tool_events)
      prices = catalog_candidates(tool_events).filter_map do |candidate|
        price = candidate['price'].to_h.deep_stringify_keys
        next if price['currency'].blank?

        if price['final_total_known'] != false && price['amount'].present?
          next price.slice('amount', 'currency').merge('kind' => 'final')
        end
        next unless price['final_total_known'] == false && price['reference_amount'].present?

        price.slice('reference_amount', 'currency').merge('amount' => price['reference_amount'], 'kind' => 'reference')
      end
      prices_by_currency_and_kind = prices.group_by { |price| price.values_at('currency', 'kind') }

      prices_by_currency_and_kind.any? do |(_currency, kind), comparable_prices|
        normalized_amounts = comparable_prices.filter_map { |price| decimal_reference_amount(price['amount']) }
        next false if normalized_amounts.uniq.size < 2

        kind == 'final' || answer.match?(CATALOG_REFERENCE_PRICE_QUALIFIER_PATTERN)
      end
    end

    def catalog_claim_supported?(tool_events, pattern)
      catalog_candidates(tool_events).any? do |candidate|
        candidate.slice('evidence', 'attributes', 'features', 'description').to_json.match?(pattern)
      end
    end

    def catalog_candidates(tool_events)
      catalog_results(tool_events).flat_map { |result| catalog_candidates_in(result) }
                                  .uniq { |candidate| candidate.values_at('item_id', 'variant_id', 'display_name') }
    end

    def catalog_candidates_in(value)
      case value
      when Hash
        value = value.deep_stringify_keys
        Array(value['candidates']).filter_map { |candidate| candidate.deep_stringify_keys if candidate.is_a?(Hash) } +
          value.each_value.flat_map { |child| catalog_candidates_in(child) }
      when Array
        value.flat_map { |child| catalog_candidates_in(child) }
      else
        []
      end
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

    def single_catalog_no_match_without_candidates?(tool_events)
      events = Array(tool_events)
      return false unless events.one?

      event = events.first
      event['tool'] == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL && no_match_without_candidates?(event['result'] || event[:result])
    end

    def no_match_without_candidates?(result)
      result = result.deep_stringify_keys if result.respond_to?(:deep_stringify_keys)
      return false unless result.is_a?(Hash)
      return false unless result['result_type'] == 'no_match'

      Array(result['candidates']).empty? && result['result_count'].to_i.zero?
    end

    def catalog_no_match_fallback_answer(tool_events)
      query = latest_catalog_query(tool_events)
      subject = query.present? ? "#{query} için " : ''

      "#{subject}net bir ürün bulamadım. Ürün adını, kategori bilgisini veya aradığınız özelliği biraz daha net paylaşır mısınız?"
    end

    def latest_catalog_query(tool_events)
      catalog_event = Array(tool_events).reverse.find { |event| event['tool'] == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL }
      return unless catalog_event

      result = catalog_event['result'] || catalog_event[:result] || {}
      args = catalog_event['args'] || catalog_event[:args] || {}
      result['query'].presence || result[:query].presence || args['query'].presence || args[:query].presence
    end

    def reference_price_leak?(answer, tool_events)
      reference_price_patterns(tool_events).any? { |pattern| answer.match?(pattern) }
    end

    def sanitize_reference_prices(answer, tool_events)
      sanitized = answer.to_s.strip.presence
      return sanitized if sanitized.blank?

      reference_price_patterns(tool_events).each do |pattern|
        sanitized = sanitized.gsub(pattern, 'gördüğünüz tutar')
      end
      sanitized.gsub(/\*\*gördüğünüz tutar\*\*\s+tutar[ıi]?/i, '**gördüğünüz tutar**')
               .gsub(/gördüğünüz\s+\*\*gördüğünüz tutar\*\*/i, 'Gördüğünüz tutar')
               .gsub(/gördüğünüz\s+gördüğünüz tutar/i, 'gördüğünüz tutar')
               .gsub(/gördüğünüz tutar\s+tutar[ıi]?/i, 'gördüğünüz tutar')
               .strip
               .presence
    end

    def reference_price_patterns(tool_events)
      reference_price_amounts(tool_events).flat_map { |amount| reference_amount_patterns(amount) }
    end

    def reference_price_amounts(tool_events)
      Array(tool_events).flat_map do |event|
        reference_price_amounts_in(event['result'] || event[:result])
      end.uniq
    end

    def reference_price_amounts_in(value)
      case value
      when Array
        value.flat_map { |item| reference_price_amounts_in(item) }
      when Hash
        amounts = reference_amounts_from_price_hash(value)
        value.each_value { |child| amounts.concat(reference_price_amounts_in(child)) }
        amounts
      else
        []
      end
    end

    def reference_amounts_from_price_hash(value)
      price = value['price'] || value[:price]
      return [] unless price.is_a?(Hash)
      return [] unless price['final_total_known'] == false || price[:final_total_known] == false

      [
        decimal_reference_amount(price['reference_amount'] || price[:reference_amount]),
        decimal_reference_amount(price['compare_at_reference_amount'] || price[:compare_at_reference_amount])
      ].compact
    end

    def decimal_reference_amount(value)
      return if value.blank?

      BigDecimal(value.to_s)
    rescue ArgumentError
      nil
    end

    def reference_amount_patterns(amount)
      formatted_decimal_amounts(amount).map do |formatted_amount|
        reference_amount_pattern(formatted_amount)
      end
    end

    def formatted_decimal_amounts(amount)
      rounded = amount.round(2)
      integer, fraction = format('%.2f', rounded).split('.')
      grouped_dot = integer.reverse.gsub(/(\d{3})(?=\d)/, '\\1.').reverse
      grouped_comma = integer.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      fractions = fraction == '00' ? [nil, '0', '00'] : [fraction.delete_suffix('0'), fraction].uniq

      fractions.flat_map do |decimal|
        next [integer, grouped_dot, grouped_comma] unless decimal

        ["#{integer}.#{decimal}", "#{integer},#{decimal}", "#{grouped_dot},#{decimal}", "#{grouped_comma}.#{decimal}"]
      end.uniq
    end

    def reference_amount_pattern(formatted_amount)
      currency = '(?:TL|TRY|USD|EUR|GBP|₺|\$|€|£)'
      amount = Regexp.escape(formatted_amount)

      Regexp.new(
        "(?<![\\d[:alpha:]])(?:[₺$€£]\\s*)?#{amount}(?:\\s*#{currency})?(?![\\d[:alpha:]]|[.,]\\d)",
        Regexp::IGNORECASE
      )
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

      'tool_evidence'
    end

    def fallback_assistant_message
      safety_handoff_message
    end
  end
end
