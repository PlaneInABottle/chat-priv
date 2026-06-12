# frozen_string_literal: true

class VoiceAgents::ToolExecutor
  def self.perform!(call:, voice_agent:, tool_key:, args:, external_id: nil)
    new(call: call, voice_agent: voice_agent, tool_key: tool_key, args: args, external_id: external_id).perform!
  end

  def initialize(call:, voice_agent:, tool_key:, args:, external_id: nil)
    @call = call
    @voice_agent = voice_agent
    @tool_key = tool_key.to_s
    @args = args.is_a?(Hash) ? args.deep_stringify_keys : {}
    @external_id = external_id
  end

  def perform!
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    definition = VoiceAgents::ToolRegistry.find(tool_key)
    rejection_code = rejection_code_for(definition)
    return record_rejection(rejection_code, started_at) if rejection_code

    result = execute_definition(definition)
    status = result[:status] == 'ok' ? 'executed' : 'error'
    event = record_event(status: status, result: result, started_at: started_at)
    { status: status, result: result, tool_event: event }
  rescue StandardError => e
    Rails.logger.error("[VoiceAgents::ToolExecutor] #{e.class}: #{e.message}")
    event = record_event(status: 'error', result: {}, error_message: e.message, started_at: started_at)
    { status: 'error', result: { status: 'error', error_message: 'Tool execution failed.' }, tool_event: event }
  end

  private

  attr_reader :call, :voice_agent, :tool_key, :args, :external_id

  def rejection_code_for(definition)
    return 'unknown_tool' unless definition
    return 'tool_not_enabled' unless config.enabled_tool?(definition.key)
    return 'voice_agent_disabled' unless voice_agent.enabled?

    validate_integration_gate(definition)
  end

  def execute_definition(definition)
    case definition.key
    when VoiceAgents::Config::HUMAN_HANDOFF_TOOL
      request_handoff
    when VoiceAgents::Config::END_CUSTOMER_CALL_TOOL
      end_call
    else
      execute_integration_tool(definition)
    end
  end

  def execute_integration_tool(definition)
    definition.service_class.constantize.new(
      ai_agent: voice_agent,
      account: call.account,
      mode: call.test_call? ? :test : :live,
      settings: config.tool_settings(definition.key),
      conversation: call.conversation,
      trigger_message: nil
    ).call(args: args)
  end

  def request_handoff
    if call.test_call? && call.conversation.blank?
      meta = (call.meta || {}).merge(
        'handoff_status' => 'requested',
        'ai_status' => 'handoff_requested',
        'test_handoff_requested_at' => Time.zone.now.iso8601(3),
        'test_handoff_reason' => args['reason'].to_s
      )
      call.update!(meta: meta)
      return {
        status: 'ok',
        terminal_action: 'handoff',
        test_mode: true,
        customer_message: 'Human handoff requested in the sandbox test call.',
        reason: args['reason'].to_s
      }
    end

    raise ArgumentError, 'Call handoff requires a conversation' unless call.conversation

    setting = voice_setting
    call.update!(handoff_status: 'requested', ai_status: 'handoff_requested')
    call.conversation.update!(team: setting&.fallback_team) if setting&.fallback_team
    Voice::CallMessageBuilder.new(call).update_status!(status: call.status)
    Voice::CallBroadcaster.safe_call_status_changed(call)
    { status: 'ok', terminal_action: 'handoff', reason: args['reason'].to_s }
  end

  def end_call
    Voice::CallFinalizer.perform!(call: call, status: 'completed', end_reason: args['reason'].presence)
    { status: 'ok', terminal_action: 'end_call', status_text: call.status, end_reason: args['reason'].to_s }
  end

  def validate_integration_gate(definition)
    return nil unless definition.requires_integration_app_id
    return nil unless definition.requires_integration_app_id == Integrations::Ikas::ConnectionStatus::IKAS_APP_ID
    return 'ikas_feature_disabled' unless call.account.feature_enabled?('ikas_integration')

    state = Integrations::Ikas::ConnectionStatus.new(account: call.account).payload[:state]
    return 'ikas_not_connected' unless state == 'connected'

    nil
  end

  def record_rejection(error_code, started_at)
    result = { status: 'error', error_code: error_code, error_message: 'Tool execution was rejected.' }
    event = record_event(status: 'rejected', result: result, started_at: started_at)
    { status: 'rejected', result: result, tool_event: event }
  end

  def record_event(status:, result:, started_at:, error_message: nil)
    Voice::ToolCallRecorder.perform!(
      call: call,
      tool: tool_key,
      status: status,
      arguments: sanitized_args,
      result: result,
      error_message: error_message,
      duration_ms: duration_ms(started_at),
      external_id: external_id
    )
  end

  def sanitized_args
    return args unless tool_key == VoiceAgents::Config::IKAS_LOOKUP_ORDER_TOOL

    sanitized = args.deep_dup
    sanitized['email'] = AiAgents::PrivacyRedactor.mask_email(sanitized['email']) if sanitized['email'].present?
    sanitized['phone'] = AiAgents::PrivacyRedactor.mask_phone(sanitized['phone']) if sanitized['phone'].present?
    sanitized
  end

  def duration_ms(started_at)
    return unless started_at

    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round
  end

  def config
    @config ||= VoiceAgents::Config.new(voice_agent.tools_config)
  end

  def voice_setting
    @voice_setting ||= call.account.voice_inbox_setting_for(
      inbox: call.inbox,
      id: call.meta&.fetch('voice_inbox_setting_id', nil)
    )
  end
end
