# frozen_string_literal: true

module AiAgents
  class Config
    HUMAN_HANDOFF_TOOL = 'human_handoff'.freeze
    IKAS_LOOKUP_ORDER_TOOL = 'ikas_lookup_order'.freeze
    IKAS_CATALOG_SEARCH_TOOL = 'ikas_catalog_search'.freeze
    KNOWLEDGE_SEARCH_TOOL = 'search_knowledge'.freeze
    PRESENT_OPTIONS_TOOL = 'present_options'.freeze
    TOOLS_KEY = 'tools'.freeze
    ENABLED_KEY = 'enabled'.freeze
    DEFAULT_ENABLED_TOOL_KEYS = [HUMAN_HANDOFF_TOOL, PRESENT_OPTIONS_TOOL].freeze
    HUMAN_HANDOFF_SETTINGS_KEYS = ['allowed_labels'].freeze
    LEGACY_HUMAN_HANDOFF_SETTINGS_KEYS = %w[preview_only transfer_message].freeze

    def initialize(config, allow_legacy_human_handoff_settings: false)
      @config = config.is_a?(Hash) ? config.deep_stringify_keys : {}
      @allow_legacy_human_handoff_settings = allow_legacy_human_handoff_settings
    end

    def valid?
      errors.empty?
    end

    def errors
      @errors ||= validate
    end

    def normalized_config
      normalized = config.deep_dup
      return normalized.merge(TOOLS_KEY => normalized_tools_config) if tools_config.nil?
      return normalized unless tools_config.is_a?(Hash)

      normalized[TOOLS_KEY] = normalized_tools_config
      normalized
    end

    def enabled_tool_keys
      @enabled_tool_keys ||= begin
        keys = [HUMAN_HANDOFF_TOOL, *Array(enabled_tools_value)].filter_map(&:presence).map(&:to_s).uniq
        if present_options_settings['enabled']
          keys << PRESENT_OPTIONS_TOOL
        else
          keys.delete(PRESENT_OPTIONS_TOOL)
        end
        keys & AiAgents::ToolRegistry.keys
      end
    end

    def enabled_tool?(tool_key)
      enabled_tool_keys.include?(tool_key.to_s)
    end

    def tool_settings(tool_key)
      normalized_tools_config.fetch(tool_key.to_s, {})
    end

    def tools_summary
      {
        ENABLED_KEY => enabled_tool_keys,
        HUMAN_HANDOFF_TOOL => human_handoff_settings,
        IKAS_LOOKUP_ORDER_TOOL => ikas_lookup_order_settings,
        IKAS_CATALOG_SEARCH_TOOL => ikas_catalog_search_settings,
        PRESENT_OPTIONS_TOOL => present_options_settings
      }
    end

    private

    attr_reader :config, :allow_legacy_human_handoff_settings

    def tools_config
      value = config[TOOLS_KEY]
      value.is_a?(Hash) ? value.deep_stringify_keys : value
    end

    def normalized_tools_config
      {
        ENABLED_KEY => enabled_tool_keys,
        HUMAN_HANDOFF_TOOL => human_handoff_settings,
        IKAS_LOOKUP_ORDER_TOOL => ikas_lookup_order_settings,
        IKAS_CATALOG_SEARCH_TOOL => ikas_catalog_search_settings,
        PRESENT_OPTIONS_TOOL => present_options_settings
      }
    end

    def enabled_tools_value
      return DEFAULT_ENABLED_TOOL_KEYS unless tools_config.is_a?(Hash) && tools_config.key?(ENABLED_KEY)

      tools_config[ENABLED_KEY]
    end

    def human_handoff_settings
      settings = tools_config&.dig(HUMAN_HANDOFF_TOOL)
      settings = settings.deep_stringify_keys if settings.is_a?(Hash)

      {
        'allowed_labels' => Array(settings&.[]('allowed_labels')).filter_map(&:presence).map(&:to_s).uniq
      }
    end

    def ikas_lookup_order_settings
      settings = tools_config&.dig(IKAS_LOOKUP_ORDER_TOOL)
      settings = settings.deep_stringify_keys if settings.is_a?(Hash)

      {
        'enabled' => settings&.key?('enabled') ? settings['enabled'] : false
      }
    end

    def ikas_catalog_search_settings
      settings = tools_config&.dig(IKAS_CATALOG_SEARCH_TOOL)
      settings.is_a?(Hash) ? settings.deep_stringify_keys : {}
    end

    def present_options_settings
      settings = tools_config&.dig(PRESENT_OPTIONS_TOOL)
      settings = settings.deep_stringify_keys if settings.is_a?(Hash)

      {
        'enabled' => settings&.key?('enabled') ? settings['enabled'] : true
      }
    end

    def validate
      return [] if config.blank?
      return ['config must be a JSON object'] unless config.is_a?(Hash)
      return [] if tools_config.nil?
      return ['config.tools must be an object'] unless tools_config.is_a?(Hash)

      [].tap do |messages|
        messages.concat(validate_enabled_tools)
        messages.concat(validate_tool_keys)
        messages.concat(validate_human_handoff_settings)
        messages.concat(validate_ikas_lookup_order_settings)
        messages.concat(validate_ikas_catalog_search_settings)
        messages.concat(validate_present_options_settings)
      end
    end

    def validate_enabled_tools
      enabled = tools_config[ENABLED_KEY]
      return [] if enabled.nil?
      return ['config.tools.enabled must be an array'] unless enabled.is_a?(Array)

      unknown_keys = enabled.filter_map(&:presence).map(&:to_s).uniq - AiAgents::ToolRegistry.keys
      return [] if unknown_keys.empty?

      ["config.tools.enabled contains unknown tools: #{unknown_keys.join(', ')}"]
    end

    def validate_tool_keys
      unknown_keys = tools_config.keys - [ENABLED_KEY, *AiAgents::ToolRegistry.keys]
      return [] if unknown_keys.empty?

      ["config.tools contains unknown keys: #{unknown_keys.join(', ')}"]
    end

    def validate_human_handoff_settings
      settings = tools_config[HUMAN_HANDOFF_TOOL]
      return [] if settings.nil?
      return ['config.tools.human_handoff must be an object'] unless settings.is_a?(Hash)

      [].tap do |messages|
        unknown_keys = settings.keys - allowed_human_handoff_settings_keys
        messages << "config.tools.human_handoff contains unknown keys: #{unknown_keys.join(', ')}" if unknown_keys.present?
        messages << 'config.tools.human_handoff.allowed_labels must be an array' if settings.key?('allowed_labels') && !settings['allowed_labels'].is_a?(Array)
      end
    end

    def validate_ikas_lookup_order_settings
      settings = tools_config[IKAS_LOOKUP_ORDER_TOOL]
      return [] if settings.nil?
      return ['config.tools.ikas_lookup_order must be an object'] unless settings.is_a?(Hash)
      return [] unless settings.key?('enabled') && !boolean?(settings['enabled'])

      ['config.tools.ikas_lookup_order.enabled must be true or false']
    end

    def validate_ikas_catalog_search_settings
      settings = tools_config[IKAS_CATALOG_SEARCH_TOOL]
      return [] if settings.nil?
      return ['config.tools.ikas_catalog_search must be an object'] unless settings.is_a?(Hash)

      unknown_keys = settings.keys
      return [] if unknown_keys.empty?

      ["config.tools.ikas_catalog_search contains unknown keys: #{unknown_keys.join(', ')}"]
    end

    def validate_present_options_settings
      settings = tools_config[PRESENT_OPTIONS_TOOL]
      return [] if settings.nil?
      return ['config.tools.present_options must be an object'] unless settings.is_a?(Hash)

      unknown_keys = settings.keys - ['enabled']
      return ["config.tools.present_options contains unknown keys: #{unknown_keys.join(', ')}"] if unknown_keys.present?
      return [] unless settings.key?('enabled') && !boolean?(settings['enabled'])

      ['config.tools.present_options.enabled must be true or false']
    end

    def allowed_human_handoff_settings_keys
      return HUMAN_HANDOFF_SETTINGS_KEYS unless allow_legacy_human_handoff_settings

      HUMAN_HANDOFF_SETTINGS_KEYS + LEGACY_HUMAN_HANDOFF_SETTINGS_KEYS
    end

    def boolean?(value)
      [true, false].include?(value)
    end

  end
end
