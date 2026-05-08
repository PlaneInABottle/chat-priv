# frozen_string_literal: true

require 'set'

module AiAgents
  class ToolExecutor
    Result = Struct.new(:status, :tool_event, :tool_result, keyword_init: true)

      def initialize(ai_agent:, account:, mode:, executed_tool_keys: Set.new, conversation: nil, trigger_message: nil)
        @ai_agent = ai_agent
        @account = account
        @mode = mode
        @executed_tool_keys = executed_tool_keys
        @config = AiAgents::Config.new(ai_agent.config, allow_legacy_human_handoff_settings: true)
        @conversation = conversation
        @trigger_message = trigger_message
      end

    def execute(tool_call)
      definition = AiAgents::ToolRegistry.find(tool_call[:name])
      return rejected_result(tool_call, 'unknown_tool') unless definition
      return rejected_result(tool_call, 'tool_not_enabled') unless config.enabled_tool?(definition.key)
      return rejected_result(tool_call, 'tool_not_allowed_in_mode') unless mode_supported?(definition)
      return rejected_result(tool_call, 'duplicate_tool_execution') if executed_tool_keys.include?(definition.key)

      integration_gate_error = validate_integration_gate(definition)
      return rejected_result(tool_call, integration_gate_error) if integration_gate_error

      args = parse_arguments(tool_call)
      return rejected_result(tool_call, 'invalid_tool_arguments') unless args

      executed_tool_keys << definition.key
        service = definition.service_class.constantize.new(
          ai_agent: ai_agent,
          account: account,
          mode: mode,
          settings: config.tool_settings(definition.key),
          conversation: conversation,
          trigger_message: trigger_message
        )
      tool_result = service.call(args: args)

      Result.new(
        status: tool_result[:status] == 'ok' ? 'executed' : 'error',
        tool_event: build_tool_event(tool_call, definition, tool_result),
        tool_result: tool_result
      )
    rescue StandardError => e
      Rails.logger.error("[AiAgents::ToolExecutor] #{e.class}: #{e.message}")
      rejected_result(tool_call, 'tool_exception')
    end

    private

    attr_reader :ai_agent, :account, :mode, :executed_tool_keys, :config, :conversation, :trigger_message

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
      return nil unless definition.key == AiAgents::Config::IKAS_LOOKUP_ORDER_TOOL
      return 'ikas_feature_disabled' unless account.feature_enabled?('ikas_integration')

      state = Integrations::Ikas::ConnectionStatus.new(account: account).payload[:state]
      return 'ikas_not_connected' unless state == 'connected'

      'ikas_contract_unverified'
    end

    def build_tool_event(tool_call, definition, tool_result)
      {
        'tool' => definition.key,
        'status' => tool_result[:status],
        'tool_call_id' => tool_call[:id],
        'terminal' => definition.terminal,
        'args' => sanitize_args(tool_call[:arguments]),
        'result' => sanitize_result(tool_result)
      }
    end

    def sanitize_args(arguments)
      JSON.parse(arguments.presence || '{}')
    rescue JSON::ParserError
      {}
    end

    def sanitize_result(tool_result)
      tool_result.except(:raw_response).deep_stringify_keys
    end

    def rejected_result(tool_call, error_code)
      Result.new(
        status: 'rejected',
        tool_event: {
          'tool' => tool_call[:name].to_s,
          'status' => 'rejected',
          'tool_call_id' => tool_call[:id],
          'error_code' => error_code
        },
        tool_result: {
          status: 'error',
          error_code: error_code,
          error_message: 'Tool execution was rejected.'
        }
      )
    end
  end
end
