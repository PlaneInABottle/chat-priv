# frozen_string_literal: true

class VoiceAgents::Config
  HUMAN_HANDOFF_TOOL = AiAgents::Config::HUMAN_HANDOFF_TOOL
  IKAS_LOOKUP_ORDER_TOOL = AiAgents::Config::IKAS_LOOKUP_ORDER_TOOL
  IKAS_CATALOG_SEARCH_TOOL = AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL
  KNOWLEDGE_SEARCH_TOOL = AiAgents::Config::KNOWLEDGE_SEARCH_TOOL
  END_CUSTOMER_CALL_TOOL = 'end_customer_call'
  ENABLED_KEY = 'enabled'
  DEFAULT_ENABLED_TOOL_KEYS = [HUMAN_HANDOFF_TOOL, END_CUSTOMER_CALL_TOOL].freeze

  def initialize(tools_config)
    @tools_config = tools_config.is_a?(Hash) ? tools_config.deep_stringify_keys : {}
  end

  def valid?
    errors.empty?
  end

  def errors
    @errors ||= validate
  end

  def normalized_config
    {
      ENABLED_KEY => enabled_tool_keys,
      HUMAN_HANDOFF_TOOL => human_handoff_settings,
      IKAS_LOOKUP_ORDER_TOOL => ikas_lookup_order_settings,
      IKAS_CATALOG_SEARCH_TOOL => ikas_catalog_search_settings,
      END_CUSTOMER_CALL_TOOL => end_customer_call_settings
    }
  end

  def enabled_tool_keys
    @enabled_tool_keys ||= begin
      keys = [*DEFAULT_ENABLED_TOOL_KEYS, *Array(enabled_tools_value)].filter_map(&:presence).map(&:to_s).uniq
      keys & VoiceAgents::ToolRegistry.keys
    end
  end

  def enabled_tool?(tool_key)
    enabled_tool_keys.include?(tool_key.to_s)
  end

  def tool_settings(tool_key)
    normalized_config.fetch(tool_key.to_s, {})
  end

  private

  attr_reader :tools_config

  def enabled_tools_value
    return DEFAULT_ENABLED_TOOL_KEYS unless tools_config.key?(ENABLED_KEY)

    tools_config[ENABLED_KEY]
  end

  def human_handoff_settings
    settings = settings_for(HUMAN_HANDOFF_TOOL)
    {
      'allowed_labels' => Array(settings['allowed_labels']).filter_map(&:presence).map(&:to_s).uniq
    }
  end

  def ikas_lookup_order_settings
    settings = settings_for(IKAS_LOOKUP_ORDER_TOOL)
    {
      'enabled' => settings.key?('enabled') ? settings['enabled'] : false
    }
  end

  def ikas_catalog_search_settings
    settings_for(IKAS_CATALOG_SEARCH_TOOL)
  end

  def end_customer_call_settings
    settings_for(END_CUSTOMER_CALL_TOOL)
  end

  def settings_for(tool_key)
    settings = tools_config[tool_key]
    settings.is_a?(Hash) ? settings.deep_stringify_keys : {}
  end

  def validate
    return ['tools_config must be a JSON object'] unless tools_config.is_a?(Hash)

    [].tap do |messages|
      messages.concat(validate_enabled_tools)
      messages.concat(validate_tool_keys)
      messages.concat(validate_tool_settings)
    end
  end

  def validate_enabled_tools
    enabled = tools_config[ENABLED_KEY]
    return [] if enabled.nil?
    return ['tools_config.enabled must be an array'] unless enabled.is_a?(Array)

    unknown_keys = enabled.filter_map(&:presence).map(&:to_s).uniq - VoiceAgents::ToolRegistry.keys
    return [] if unknown_keys.empty?

    ["tools_config.enabled contains unknown tools: #{unknown_keys.join(', ')}"]
  end

  def validate_tool_keys
    unknown_keys = tools_config.keys - [ENABLED_KEY, *VoiceAgents::ToolRegistry.keys]
    return [] if unknown_keys.empty?

    ["tools_config contains unknown keys: #{unknown_keys.join(', ')}"]
  end

  def validate_tool_settings
    VoiceAgents::ToolRegistry.keys.flat_map do |tool_key|
      settings = tools_config[tool_key]
      settings.nil? || settings.is_a?(Hash) ? [] : ["tools_config.#{tool_key} must be an object"]
    end
  end
end
