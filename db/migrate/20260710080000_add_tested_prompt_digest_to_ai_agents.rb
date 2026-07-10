class AddTestedPromptDigestToAiAgents < ActiveRecord::Migration[7.1]
  def up
    add_column :ai_agents, :last_tested_prompt_digest, :string

    migration_ai_agent = Class.new(ActiveRecord::Base) do
      self.table_name = 'ai_agents'
    end
    migration_ai_agent.reset_column_information
    migration_ai_agent.where.not(last_tested_at: nil).find_each do |ai_agent|
      # rubocop:disable Rails/SkipsModelValidations
      ai_agent.update_columns(last_tested_prompt_digest: Digest::SHA256.hexdigest(ai_agent.prompt.to_s))
      # rubocop:enable Rails/SkipsModelValidations
    end
  end

  def down
    remove_column :ai_agents, :last_tested_prompt_digest
  end
end
