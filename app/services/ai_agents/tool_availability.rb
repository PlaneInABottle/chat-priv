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
    [AiAgents::Config::HUMAN_HANDOFF_TOOL, *Array(keys)].map(&:to_s).uniq & available_keys(definitions)
  end

  def filter_tools_config(tools_config, definitions)
    config = tools_config.is_a?(Hash) ? tools_config.deep_stringify_keys : {}
    config['enabled'] = filter_enabled_keys(config['enabled'], definitions)
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

    return ikas_catalog_images_ready? if definition.key == AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL
    return ikas_catalog_ready? if definition.key == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL

    true
  end

  def ikas_catalog_ready?
    catalog_snapshot&.sqlite_exists?
  end

  def ikas_catalog_images_ready?
    return false unless ikas_catalog_ready?

    db = SQLite3::Database.new(catalog_snapshot.sqlite_path)
    db.get_first_value('SELECT 1 FROM catalog_item_images LIMIT 1') == 1
  rescue SQLite3::Exception, Errno::ENOENT
    false
  ensure
    db&.close
  end

  def catalog_snapshot
    @catalog_snapshot ||= ikas_summary[:hook]
                          &.ikas_catalog_snapshots
                          &.storefront_catalog
                          &.latest_completed
                          &.first
  end

  def ikas_summary
    @ikas_summary ||= Integrations::Ikas::ConnectionStatus.new(account: account).payload
  end
end
