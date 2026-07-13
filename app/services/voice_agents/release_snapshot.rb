# frozen_string_literal: true

class VoiceAgents::ReleaseSnapshot
  ATTRIBUTES = %w[greeting prompt architecture provider model voice language config tools_config].freeze

  def self.for(agent)
    agent.attributes.slice(*ATTRIBUTES).deep_stringify_keys.merge(
      'knowledge_sources' => AiKnowledgeSources::Snapshot.for(agent)
    )
  end
end
