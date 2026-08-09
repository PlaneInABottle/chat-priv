# frozen_string_literal: true

require 'pathname'

begin
  require 'active_model'
rescue LoadError
  # Keep ChatwootApp loadable outside the Rails bundle.
end

module ChatwootApp
  def self.root
    Pathname.new(File.expand_path('..', __dir__))
  end

  def self.max_limit
    100_000
  end

  def self.enterprise?
    return false if enterprise_disabled?

    root.join('enterprise').exist?
  end

  def self.chatwoot_cloud?
    return false unless enterprise?

    deployment_env = ENV.fetch('DEPLOYMENT_ENV', nil)
    return deployment_env == 'cloud' if deployment_env.present?

    begin
      GlobalConfig.get_value('DEPLOYMENT_ENV') == 'cloud'
    rescue StandardError => e
      Rails.logger.debug { "Error checking chatwoot_cloud: #{e.message}" }
      false
    end
  end

  def self.self_hosted_enterprise?
    enterprise? && !chatwoot_cloud? && GlobalConfig.get_value('INSTALLATION_PRICING_PLAN') == 'enterprise'
  end

  def self.custom?
    @custom ||= root.join('custom').exist?
  end

  def self.help_center_root
    ENV.fetch('HELPCENTER_URL', nil) || ENV.fetch('FRONTEND_URL', nil)
  end

  def self.extensions
    if custom?
      %w[enterprise custom]
    elsif enterprise?
      %w[enterprise]
    else
      %w[]
    end
  end

  def self.advanced_search_allowed?
    enterprise? && ENV.fetch('OPENSEARCH_URL', nil).present?
  end

  def self.otel_enabled?
    return false unless database_ready?

    begin
      otel_provider = InstallationConfig.find_by(name: 'OTEL_PROVIDER')&.value
      secret_key = InstallationConfig.find_by(name: 'LANGFUSE_SECRET_KEY')&.value

      otel_provider.present? && secret_key.present? && otel_provider == 'langfuse'
    rescue StandardError => e
      Rails.logger.debug { "Error checking otel_enabled: #{e.message}" }
      false
    end
  end

  class << self
    private

    def enterprise_disabled?
      boolean_value(ENV.fetch('DISABLE_ENTERPRISE', nil))
    end

    def boolean_value(value)
      return ActiveModel::Type::Boolean.new.cast(value) if defined?(ActiveModel::Type::Boolean)

      value = value.to_s.strip.downcase
      case value
      when '', 'false', '0', 'f', 'off'
        false
      else
        true
      end
    end

    def database_ready?
      ActiveRecord::Base.connected? && InstallationConfig.table_exists?
    rescue StandardError
      false
    end
  end
end
