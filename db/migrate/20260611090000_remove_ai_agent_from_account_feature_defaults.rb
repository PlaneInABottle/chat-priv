class RemoveAiAgentFromAccountFeatureDefaults < ActiveRecord::Migration[7.1]
  def up
    # AI Agent access is controlled by account settings, not bigint feature flags.
    # The ai_agent flag sits beyond the signed bigint flag capacity and can make
    # new account creation overflow when enabled by default.
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    config.value = config.value.reject { |feature| feature['name'] == 'ai_agent' }
    config.save!
    GlobalConfig.clear_cache
  end

  def down
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?
    return if config.value.any? { |feature| feature['name'] == 'ai_agent' }

    config.value = config.value + [
      {
        'name' => 'ai_agent',
        'display_name' => 'AI Asistan',
        'enabled' => true,
        'help_url' => 'https://chwt.app/hc/ai-asistan'
      }
    ]
    config.save!
    GlobalConfig.clear_cache
  end
end
