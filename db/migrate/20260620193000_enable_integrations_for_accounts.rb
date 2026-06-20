class EnableIntegrationsForAccounts < ActiveRecord::Migration[7.1]
  def up
    update_feature_default!

    Account.find_in_batches(batch_size: 100) do |accounts|
      accounts.each { |account| account.enable_features!('integrations') }
    end

    GlobalConfig.clear_cache
  end

  def down
    update_feature_default!(enabled: false)

    GlobalConfig.clear_cache
  end

  private

  def update_feature_default!(enabled: true)
    config = InstallationConfig.find_by(name: 'ACCOUNT_LEVEL_FEATURE_DEFAULTS')
    return if config&.value.blank?

    features = config.value.map do |feature|
      feature['name'] == 'integrations' ? feature.merge('enabled' => enabled) : feature
    end
    config.update!(value: features)
  end
end
