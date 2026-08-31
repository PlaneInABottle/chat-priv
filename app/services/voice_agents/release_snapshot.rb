# frozen_string_literal: true

class VoiceAgents::ReleaseSnapshot
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
    sanitized.merge('config' => config.except(VoiceAgents::AuthoringProfile::RESERVED_KEY))
  end
end
