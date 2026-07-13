# frozen_string_literal: true

class AiAgents::ReleaseSnapshot
  def self.for(agent)
    {
      'prompt' => agent.prompt.to_s,
      'config' => agent.config.to_h.deep_stringify_keys,
      'knowledge_sources' => AiKnowledgeSources::Snapshot.for(agent)
    }
  end

  def self.fingerprint(snapshot)
    normalized = snapshot.deep_stringify_keys
    AssistantReleases::Snapshot.fingerprint(
      'prompt' => normalized['prompt'].to_s,
      'config' => normalized['config'].to_h.except('instructions'),
      'knowledge_sources' => normalized['knowledge_sources'].to_a
    )
  end
end
