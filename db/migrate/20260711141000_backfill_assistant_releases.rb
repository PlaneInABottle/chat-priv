class BackfillAssistantReleases < ActiveRecord::Migration[7.1]
  MigrationAiAgent = Class.new(ActiveRecord::Base) do
    self.table_name = 'ai_agents'
  end

  MigrationAiAgentRelease = Class.new(ActiveRecord::Base) do
    self.table_name = 'ai_agent_releases'
  end

  MigrationVoiceAgent = Class.new(ActiveRecord::Base) do
    self.table_name = 'voice_agents'
  end

  MigrationVoiceAgentRelease = Class.new(ActiveRecord::Base) do
    self.table_name = 'voice_agent_releases'
  end

  def up
    backfill_ai_agents
    backfill_voice_agents
  end

  def down
    # Historical rows may not satisfy current model validations during rollback.
    # rubocop:disable Rails/SkipsModelValidations
    MigrationAiAgent.update_all(current_release_id: nil)
    MigrationVoiceAgent.update_all(current_release_id: nil, last_tested_draft_fingerprint: nil)
    # rubocop:enable Rails/SkipsModelValidations
    MigrationAiAgentRelease.delete_all
    MigrationVoiceAgentRelease.delete_all
  end

  private

  def backfill_ai_agents
    MigrationAiAgent.where('published_revision > 0').find_each do |agent|
      snapshot = { 'prompt' => agent.published_prompt.to_s, 'config' => agent.published_config || {} }
      release = MigrationAiAgentRelease.create!(ai_release_attributes(agent, snapshot))
      # rubocop:disable Rails/SkipsModelValidations
      agent.update_columns(current_release_id: release.id)
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def backfill_voice_agents
    MigrationVoiceAgent.where('published_at IS NOT NULL OR enabled = TRUE').find_each do |agent|
      snapshot = agent.attributes.slice(*voice_snapshot_attributes)
      release = MigrationVoiceAgentRelease.create!(voice_release_attributes(agent, snapshot))
      # rubocop:disable Rails/SkipsModelValidations
      agent.update_columns(
        current_release_id: release.id,
        last_tested_draft_fingerprint: release.fingerprint
      )
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def ai_release_attributes(agent, snapshot)
    timestamp = agent.published_at || agent.updated_at
    {
      account_id: agent.account_id,
      ai_agent_id: agent.id,
      revision: agent.published_revision,
      source: 'migration',
      fingerprint: fingerprint(ai_runtime_snapshot(snapshot)),
      snapshot: snapshot,
      created_at: timestamp,
      updated_at: timestamp
    }
  end

  def ai_runtime_snapshot(snapshot)
    {
      'prompt' => snapshot['prompt'],
      'config' => snapshot['config'].to_h.deep_stringify_keys.except('instructions')
    }
  end

  def voice_release_attributes(agent, snapshot)
    timestamp = agent.published_at || agent.updated_at
    {
      account_id: agent.account_id,
      voice_agent_id: agent.id,
      revision: 1,
      source: 'migration',
      fingerprint: fingerprint(snapshot),
      snapshot: snapshot,
      created_at: timestamp,
      updated_at: timestamp
    }
  end

  def voice_snapshot_attributes
    %w[greeting prompt architecture provider model voice language config tools_config]
  end

  def fingerprint(snapshot)
    Digest::SHA256.hexdigest(JSON.generate(canonicalize(snapshot)))
  end

  def canonicalize(value)
    case value
    when Hash
      value.keys.sort.index_with { |key| canonicalize(value[key]) }
    when Array
      value.map { |item| canonicalize(item) }
    else
      value
    end
  end
end
