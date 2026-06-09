class Voice::ToolCallRecorder
  MAX_EVENTS = 50
  VALID_STATUSES = %w[started executed error rejected].freeze
  MAX_TEXT_LENGTH = 2000

  def self.perform!(call:, tool:, status:, arguments: {}, result: {}, error_message: nil, duration_ms: nil)
    new(
      call: call,
      tool: tool,
      status: status,
      arguments: arguments,
      result: result,
      error_message: error_message,
      duration_ms: duration_ms
    ).perform!
  end

  def initialize(call:, tool:, status:, arguments: {}, result: {}, error_message: nil, duration_ms: nil)
    @call = call
    @tool = tool.to_s.presence || 'unknown_tool'
    @status = VALID_STATUSES.include?(status.to_s) ? status.to_s : 'executed'
    @arguments = arguments
    @result = result
    @error_message = error_message
    @duration_ms = duration_ms
  end

  def perform!
    event = build_event
    meta = call.meta.is_a?(Hash) ? call.meta.deep_dup : {}
    events = Array(meta['voice_tool_events']).select { |item| item.is_a?(Hash) }
    events << event
    meta['voice_tool_events'] = events.last(MAX_EVENTS)
    meta['last_voice_tool_event'] = event
    call.update!(meta: meta)
    event
  end

  private

  attr_reader :call, :tool, :status, :arguments, :result, :error_message, :duration_ms

  def build_event
    {
      'id' => SecureRandom.uuid,
      'tool' => tool.truncate(120),
      'status' => status,
      'arguments' => sanitize(arguments),
      'result' => sanitize(result),
      'error_message' => sanitize_text(error_message),
      'duration_ms' => normalized_duration_ms,
      'source' => 'livekit_agent',
      'created_at' => Time.zone.now.iso8601(3)
    }.compact
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
