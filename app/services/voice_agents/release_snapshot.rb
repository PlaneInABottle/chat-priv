# frozen_string_literal: true

class VoiceAgents::ReleaseSnapshot
  LEGACY_AUTHORING_PROFILE_KEY = 'authoring_profile'
  ATTRIBUTES = %w[greeting prompt architecture provider model voice language config tools_config].freeze
  ALLOWED_KEYS = [*ATTRIBUTES, 'knowledge_sources'].freeze

  def self.for(agent)
    sanitize(agent.attributes.slice(*ATTRIBUTES).deep_stringify_keys.merge(
               'knowledge_sources' => AiKnowledgeSources::Snapshot.for(agent)
             ))
  end

  def self.sanitize(snapshot)
    sanitized = snapshot.is_a?(Hash) ? snapshot.deep_stringify_keys.slice(*ALLOWED_KEYS) : {}
    config = sanitized['config'].is_a?(Hash) ? sanitized['config'].deep_dup : {}
    config = config.except(LEGACY_AUTHORING_PROFILE_KEY)
    instructions = canonical_instructions(config['instructions'])
    config = config.except('instructions')
    return sanitized.merge('config' => config) unless instructions

    document = VoiceAgents::InstructionDocument.new(instructions)
    sanitized.merge('prompt' => document.compile, 'config' => config.merge('instructions' => instructions))
  end

  def self.canonical_instructions(value)
    VoiceAgents::InstructionDocument.new(value).normalized
  rescue ArgumentError, KeyError
    nil
  end

  private_class_method :canonical_instructions
end
