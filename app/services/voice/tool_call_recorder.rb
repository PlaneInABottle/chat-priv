require 'digest'

class Voice::ToolCallRecorder
  VALID_STATUSES = %w[started executed error rejected].freeze
  MAX_TEXT_LENGTH = 2000

  def self.perform!(call:, tool:, status:, arguments: {}, result: {}, error_message: nil, duration_ms: nil, external_id: nil)
    new(
      call: call,
      tool: tool,
      status: status,
      arguments: arguments,
      result: result,
      error_message: error_message,
      duration_ms: duration_ms,
      external_id: external_id
    ).perform!
  end

  def initialize(call:, tool:, status:, arguments: {}, result: {}, error_message: nil, duration_ms: nil, external_id: nil)
    @call = call
    @tool = tool.to_s.presence || 'unknown_tool'
    @status = VALID_STATUSES.include?(status.to_s) ? status.to_s : 'executed'
    @arguments = arguments
    @result = result
    @error_message = error_message
    @duration_ms = duration_ms
    @external_id = external_id
  end

  def perform!
    return existing_event if existing_event

    event = call.voice_tool_events.create!(
      account: call.account,
      tool: tool,
      status: status,
      arguments: sanitize(arguments),
      result: sanitize(result),
      error_message: sanitize_text(error_message),
      duration_ms: normalized_duration_ms,
      source: 'livekit_agent',
      external_id: resolved_external_id
    )
    Voice::CallBroadcaster.tool_event(call, event)
    event
  end

  private

  attr_reader :call, :tool, :status, :arguments, :result, :error_message, :duration_ms, :external_id

  def existing_event
    return if resolved_external_id.blank?

    @existing_event ||= call.voice_tool_events.find_by(external_id: resolved_external_id)
  end

  def resolved_external_id
    @resolved_external_id ||= begin
      return external_id.to_s if external_id.present?

      fingerprint_payload = {
        tool: tool,
        status: status,
        arguments: sanitize(arguments),
        result: sanitize(result),
        error_message: sanitize_text(error_message),
        duration_ms: normalized_duration_ms,
      }
      Digest::SHA256.hexdigest(fingerprint_payload.to_json)[0, 24]
    end
  end

  def normalized_duration_ms
    return if duration_ms.blank?

    Integer(duration_ms)
  rescue ArgumentError, TypeError
    nil
  end

  def sanitize(value)
    normalized = normalize_params(value)
    case normalized
    when Hash
      normalized.each_with_object({}) do |(key, item), memo|
        memo[key.to_s.truncate(120)] = sanitize(item)
      end
    when Array
      normalized.first(25).map { |item| sanitize(item) }
    when String
      sanitize_text(normalized)
    when Numeric, TrueClass, FalseClass
      normalized
    else
      sanitize_text(normalized)
    end
  end

  def normalize_params(value)
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    return value.to_h if value.respond_to?(:to_h) && !value.is_a?(Array)

    value
  end

  def sanitize_text(value)
    return if value.nil?

    AiAgents::PrivacyRedactor.redact_text(value).truncate(MAX_TEXT_LENGTH)
  end
end
