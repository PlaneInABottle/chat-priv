class AddPublishedReleaseToAiAgents < ActiveRecord::Migration[7.1]
  def up
    add_column :ai_agents, :published_prompt, :text
    add_column :ai_agents, :published_config, :jsonb, default: {}, null: false
    add_column :ai_agents, :published_revision, :integer, default: 0, null: false

    execute <<~SQL.squish
      UPDATE ai_agents
      SET published_prompt = prompt,
          published_config = COALESCE(config, '{}'::jsonb),
          published_revision = 1
      WHERE published_at IS NOT NULL OR enabled = TRUE
    SQL

    refresh_tested_release_digests
  end

  def down
    remove_column :ai_agents, :published_revision
    remove_column :ai_agents, :published_config
    remove_column :ai_agents, :published_prompt
  end

  private

  def refresh_tested_release_digests
    migration_ai_agent = Class.new(ActiveRecord::Base) do
      self.table_name = 'ai_agents'
    end
    migration_ai_agent.reset_column_information
    migration_ai_agent.where.not(last_tested_at: nil).find_each do |ai_agent|
      payload = {
        'prompt' => ai_agent.prompt.to_s,
        'config' => ai_agent.config.to_h.deep_stringify_keys.except('instructions')
      }
      digest = Digest::SHA256.hexdigest(JSON.generate(canonicalize(payload)))
      # rubocop:disable Rails/SkipsModelValidations -- migration data does not use the application model
      ai_agent.update_columns(last_tested_prompt_digest: digest)
      # rubocop:enable Rails/SkipsModelValidations
    end
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
