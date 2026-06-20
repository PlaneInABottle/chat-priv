# frozen_string_literal: true

class AiAgents::ToolAvailability
  def initialize(account:)
    @account = account
  end

  def available_definitions(definitions)
    definitions.select { |definition| available?(definition) }
  end

  def available_keys(definitions)
    available_definitions(definitions).map(&:key)
  end

  def filter_enabled_keys(keys, definitions)
    Array(keys).map(&:to_s) & available_keys(definitions)
  end

  def filter_tools_config(tools_config, definitions)
    config = tools_config.is_a?(Hash) ? tools_config.deep_stringify_keys : {}
    config['enabled'] = filter_enabled_keys(config['enabled'], definitions) if config.key?('enabled')
    if unavailable?(AiAgents::Config::IKAS_LOOKUP_ORDER_TOOL, definitions) && config['ikas_lookup_order'].is_a?(Hash)
      config['ikas_lookup_order']['enabled'] = false
    end
    config
  end

  private

  attr_reader :account

  def available?(definition)
    app_id = definition.requires_integration_app_id
    return true if app_id.blank?
    return ikas_tool_available?(definition) if app_id == Integrations::Ikas::ConnectionStatus::IKAS_APP_ID

    false
  end

  def unavailable?(tool_key, definitions)
    definition = definitions.find { |item| item.key == tool_key }
    definition.present? && !available?(definition)
  end

  def ikas_tool_available?(definition)
    return false unless account.feature_enabled?('ikas_integration')
    return false unless ikas_summary[:state] == 'connected'

    return ikas_catalog_ready? if definition.key == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL

    true
  end

  def ikas_catalog_ready?
    ikas_summary[:hook]
      &.ikas_catalog_snapshots
      &.storefront_catalog
      &.latest_completed
      &.first
      &.sqlite_exists?
  end

  def ikas_summary
    @ikas_summary ||= Integrations::Ikas::ConnectionStatus.new(account: account).payload
  end
end
