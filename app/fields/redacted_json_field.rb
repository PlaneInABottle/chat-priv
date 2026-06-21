require 'administrate/field/base'

class RedactedJsonField < Administrate::Field::Base
  SENSITIVE_KEY_PATTERN = /(password|secret|token|access[_-]?key|api[_-]?key|credential)/i
  REDACTED_VALUE = '[redacted]'.freeze

  def redacted_data
    redact(data)
  end

  def to_s
    value = redacted_data
    return value if value.is_a?(String)

    JSON.pretty_generate(value)
  rescue JSON::GeneratorError
    value.to_s
  end

  private

  def redact(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, item), result|
        result[key] = sensitive_key?(key) ? REDACTED_VALUE : redact(item)
      end
    when Array
      value.map { |item| redact(item) }
    else
      value
    end
  end

  def sensitive_key?(key)
    key.to_s.match?(SENSITIVE_KEY_PATTERN)
  end
end
