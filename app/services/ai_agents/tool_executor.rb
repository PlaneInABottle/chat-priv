# frozen_string_literal: true

class AiAgents::ToolExecutor
  Result = Struct.new(:status, :tool_event, :tool_result, keyword_init: true)

  def initialize(ai_agent:, account:, mode:, executed_tool_keys: Set.new, context: {})
    @ai_agent = ai_agent
    @account = account
    @mode = mode
    @executed_tool_keys = executed_tool_keys
    @config = AiAgents::Config.new(context[:config] || ai_agent.config, allow_legacy_human_handoff_settings: true)
    @conversation = context[:conversation]
    @trigger_message = context[:trigger_message]
    @knowledge_sources = Array(context[:knowledge_sources]).map { |source| source.to_h.deep_stringify_keys }
    @tool_events = Array(context[:tool_events])
  end

  def execute(tool_call)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    definition = AiAgents::ToolRegistry.find(tool_call[:name])
    rejection_code = rejection_code_for(definition)
    return rejected_result(tool_call, rejection_code, started_at: started_at, definition: definition) if rejection_code

    args = parse_arguments(tool_call)
    return rejected_result(tool_call, 'invalid_tool_arguments', started_at: started_at, definition: definition, args: {}) unless args

    executed_tool_keys << definition.key
    tool_result = service_for(definition).call(args: args)
    status = tool_result[:status] == 'ok' ? 'executed' : 'error'
    log_tool_execution(tool_call, definition, status, log_payload(tool_result, args, started_at, definition))

    Result.new(
      status: status,
      tool_event: build_tool_event(tool_call, definition, tool_result),
      tool_result: tool_result
    )
  rescue StandardError => e
    Rails.logger.error("[AiAgents::ToolExecutor] #{e.class}: #{e.message}")
    rejected_result(tool_call, 'tool_exception', started_at: started_at, definition: definition)
  end

  private

  attr_reader :ai_agent, :account, :mode, :executed_tool_keys, :config, :conversation, :trigger_message, :knowledge_sources, :tool_events

  def tool_execution_logger
    @tool_execution_logger ||= AiAgents::ToolExecutionLogger.new(
      ai_agent: ai_agent,
      account: account,
      conversation: conversation,
      trigger_message: trigger_message,
      mode: mode
    )
  end

  def rejection_code_for(definition)
    return 'unknown_tool' unless definition
    return 'tool_not_enabled' unless tool_enabled?(definition.key)
    return 'tool_not_allowed_in_mode' unless mode_supported?(definition)
    return 'duplicate_tool_execution' if duplicate_tool_execution?(definition)

    validate_integration_gate(definition)
  end

  def tool_enabled?(tool_key)
    return knowledge_sources.present? if tool_key == AiAgents::Config::KNOWLEDGE_SEARCH_TOOL
    if tool_key == AiAgents::Config::PRESENT_OPTIONS_TOOL
      return config.enabled_tool?(tool_key) && AiAgents::ChannelCapabilities.present_options?(mode: mode, conversation: conversation)
    end
    if tool_key == AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL
      return config.enabled_tool?(tool_key) && AiAgents::ChannelCapabilities.catalog_product_images?(mode: mode, conversation: conversation)
    end

    config.enabled_tool?(tool_key)
  end

  def duplicate_tool_execution?(definition)
    return false if definition.key.in?([AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL, AiAgents::Config::KNOWLEDGE_SEARCH_TOOL])

    executed_tool_keys.include?(definition.key)
  end

  def service_for(definition)
    context = {
      ai_agent: ai_agent,
      account: account,
      mode: mode,
      settings: config.tool_settings(definition.key),
      conversation: conversation,
      trigger_message: trigger_message
    }
    context[:knowledge_sources] = knowledge_sources if definition.key == AiAgents::Config::KNOWLEDGE_SEARCH_TOOL
    if definition.key.in?([AiAgents::Config::PRESENT_OPTIONS_TOOL, AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL])
      context[:tool_events] = tool_events
    end
    definition.service_class.constantize.new(**context)
  end

  def log_payload(tool_result, args, started_at, definition)
    {
      tool_result: sanitize_result(tool_result),
      args: sanitize_parsed_args(args, definition),
      duration_ms: duration_ms(started_at)
    }
  end

  def log_tool_execution(tool_call, definition, status, payload)
    tool_execution_logger.call(
      tool_call: tool_call,
      definition: definition,
      status: status,
      payload: payload
    )
  rescue StandardError => e
    Rails.logger.error("[AiAgents::ToolExecutionLogger] #{e.class}: #{e.message}")
  end

  def duration_ms(started_at)
    return unless started_at

    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end

  def parse_arguments(tool_call)
    JSON.parse(tool_call[:arguments].presence || '{}')
  rescue JSON::ParserError
    nil
  end

  def mode_supported?(definition)
    return true if definition.mode_support == 'both'
    return mode.to_s == 'test' if definition.mode_support == 'test_only'
    return mode.to_s == 'live' if definition.mode_support == 'live_only'

    false
  end

  def validate_integration_gate(definition)
    return nil unless definition.requires_integration_app_id
    return nil unless definition.requires_integration_app_id == Integrations::Ikas::ConnectionStatus::IKAS_APP_ID
    return 'ikas_feature_disabled' unless account.feature_enabled?('ikas_integration')

    state = Integrations::Ikas::ConnectionStatus.new(account: account).payload[:state]
    return 'ikas_not_connected' unless state == 'connected'

    nil
  end

  def build_tool_event(tool_call, definition, tool_result)
    {
      'tool' => definition.key,
      'status' => tool_result[:status],
      'tool_call_id' => tool_call[:id],
      'terminal' => definition.terminal,
      'args' => sanitize_args(tool_call[:arguments], definition: definition),
      'result' => sanitize_result(tool_result)
    }
  end

  def sanitize_args(arguments, definition: nil)
    sanitize_parsed_args(JSON.parse(arguments.presence || '{}'), definition)
  rescue JSON::ParserError
    {}
  end

  def sanitize_result(tool_result)
    result = tool_result.except(:raw_response).deep_stringify_keys
    return result unless result['terminal_action'] == AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL

    result.deep_dup.tap do |sanitized|
      Array(sanitized.dig('presentation', 'items')).each { |item| item['images'] = Array.new(Array(item['images']).length, '[stored image]') }
    end
  end

  def rejected_result(tool_call, error_code, started_at: nil, definition: nil, args: nil)
    tool_result = rejected_tool_result(error_code)

    if started_at
      payload = rejection_log_payload(tool_call, tool_result, args, started_at, definition)
      log_tool_execution(tool_call, definition, 'rejected', payload)
    end

    Result.new(status: 'rejected', tool_event: rejected_tool_event(tool_call, error_code), tool_result: tool_result)
  end

  def rejected_tool_event(tool_call, error_code)
    { 'tool' => tool_call[:name].to_s, 'status' => 'rejected', 'tool_call_id' => tool_call[:id], 'error_code' => error_code }
  end

  def rejection_log_payload(tool_call, tool_result, args, started_at, definition)
    {
      tool_result: tool_result,
      args: rejection_args(tool_call, args, definition),
      duration_ms: duration_ms(started_at)
    }
  end

  def rejection_args(tool_call, args, definition)
    return sanitize_parsed_args(args, definition) if args

    sanitize_args(tool_call[:arguments], definition: definition)
  end

  def rejected_tool_result(error_code)
    { status: 'error', error_code: error_code, error_message: 'Tool execution was rejected.' }
  end

  def sanitize_parsed_args(args, definition)
    sanitized = args.deep_dup
    return sanitized unless definition&.key == AiAgents::Config::IKAS_LOOKUP_ORDER_TOOL

    sanitized['email'] = AiAgents::PrivacyRedactor.mask_email(sanitized['email']) if sanitized['email'].present?
    sanitized['phone'] = AiAgents::PrivacyRedactor.mask_phone(sanitized['phone']) if sanitized['phone'].present?
    sanitized
  end
end
