# frozen_string_literal: true

class AiAgents::ReleaseSnapshot
  def self.for(agent)
    {
      'prompt' => agent.prompt.to_s,
      'config' => agent.config.to_h.deep_stringify_keys
    }
  end

  def self.fingerprint(snapshot)
    normalized = snapshot.deep_stringify_keys
    AssistantReleases::Snapshot.fingerprint(
      'prompt' => normalized['prompt'].to_s,
      'config' => normalized['config'].to_h.except('instructions')
    )
  end
end
