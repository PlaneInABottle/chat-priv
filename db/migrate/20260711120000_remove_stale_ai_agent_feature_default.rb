class RemoveStaleAiAgentFeatureDefault < ActiveRecord::Migration[7.1]
  def up
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    config.update!(value: config.value.reject { |feature| feature['name'] == 'ai_agent' })
    GlobalConfig.clear_cache
  end

  def down
    # Text AI access is intentionally controlled by Account#ai_agent_enabled?.
  end
end
