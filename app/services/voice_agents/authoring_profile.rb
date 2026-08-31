# frozen_string_literal: true

class VoiceAgents::AuthoringProfile
  RESERVED_KEY = 'authoring_profile'
  TONES = %w[friendly professional concise].freeze
  TEXT_LIMIT = 2000
  DEFAULTS = {
    'tone' => 'friendly',
    'business_context' => '',
    'boundaries' => ''
  }.freeze

  def self.normalize(value)
    profile = value.is_a?(Hash) ? value.deep_stringify_keys : {}
    {
      'tone' => TONES.include?(profile['tone']) ? profile['tone'] : DEFAULTS['tone'],
      'business_context' => normalized_text(profile['business_context']),
      'boundaries' => normalized_text(profile['boundaries'])
    }
  end

  def self.merge(current, changes)
    errors = validation_errors(changes)
    raise ArgumentError, errors.join(', ') if errors.any?

    normalize(current).merge(changes.deep_stringify_keys.slice(*DEFAULTS.keys))
  end

  def self.validation_errors(value)
    return ['must be an object'] unless value.is_a?(Hash)

    profile = value.deep_stringify_keys.slice(*DEFAULTS.keys)
    profile.each_with_object([]) do |(key, field_value), errors|
      if key == 'tone'
        errors << 'tone is invalid' unless TONES.include?(field_value)
      elsif !field_value.is_a?(String)
        errors << "#{key} must be a string"
      elsif field_value.length > TEXT_LIMIT
        errors << "#{key} is too long (maximum is #{TEXT_LIMIT} characters)"
      end
    end
  end

  def self.normalized_text(value)
    value.is_a?(String) && value.length <= TEXT_LIMIT ? value : ''
  end

  private_class_method :normalized_text
end
