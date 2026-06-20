# frozen_string_literal: true

class VoiceAgents::Serializer
  def initialize(voice_agent)
    @voice_agent = voice_agent
  end

  def payload
    tool_config = VoiceAgents::Config.new(voice_agent.tools_config)
    normalized_tools_config = tool_config.normalized_config
    visible_tool_keys = tool_availability.available_keys(VoiceAgents::ToolRegistry.available_definitions)
    normalized_tools_config[VoiceAgents::Config::ENABLED_KEY] &= visible_tool_keys

    {
      id: voice_agent.id,
      account_id: voice_agent.account_id,
      name: voice_agent.name,
      enabled: voice_agent.enabled,
      greeting: voice_agent.greeting,
      prompt: voice_agent.prompt,
      architecture: voice_agent.architecture,
      provider: voice_agent.provider,
      model: voice_agent.model,
      voice: voice_agent.voice,
      language: voice_agent.language,
      config: voice_agent.config,
      tools_config: normalized_tools_config,
      enabled_tool_keys: tool_config.enabled_tool_keys & visible_tool_keys,
      available_tools: available_tools,
      inbox_settings: inbox_settings,
      ikas_integration: ikas_integration,
      created_at: voice_agent.created_at,
      updated_at: voice_agent.updated_at
    }
  end

  private

  attr_reader :voice_agent

  def available_tools
    tool_availability.available_definitions(VoiceAgents::ToolRegistry.available_definitions).map do |tool|
      {
        key: tool.key,
        name: tool.name,
        description: tool.description,
        mode_support: tool.mode_support,
        terminal: tool.terminal
      }
    end
  end

  def tool_availability
    @tool_availability ||= AiAgents::ToolAvailability.new(account: voice_agent.account)
  end

  def inbox_settings
    voice_agent.voice_inbox_settings.includes(:inbox).order(:created_at).map do |setting|
      Voice::InboxSettingSerializer.new(setting).payload
    end
  end

  def ikas_integration
    summary = Integrations::Ikas::ConnectionStatus.new(account: voice_agent.account).payload
    payload = {
      feature_enabled: voice_agent.account.feature_enabled?('ikas_integration'),
      state: summary[:state],
      can_connect: summary[:can_connect]
    }

    hook = summary[:hook]
    return payload unless hook

    latest_snapshot = hook.ikas_catalog_snapshots.order(created_at: :desc, id: :desc).first
    completed_snapshot = hook.ikas_catalog_snapshots.storefront_catalog.latest_completed.first
    payload.merge(
      catalog_sync: {
        status: latest_snapshot&.status || 'not_synced',
        last_synced_at: completed_snapshot&.completed_at&.iso8601,
        products_count: completed_snapshot&.counts&.[]('products').to_i,
        catalog_items_count: completed_snapshot&.counts&.[]('catalog_items').to_i,
        error_message: latest_snapshot&.failed? ? latest_snapshot.error_message : nil
      }
    )
  end
end
