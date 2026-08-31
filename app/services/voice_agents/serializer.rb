# frozen_string_literal: true

class VoiceAgents::Serializer
  BASE_ATTRIBUTES = %w[
    id account_id name enabled greeting prompt architecture provider model voice language config created_at updated_at
  ].freeze

  def initialize(voice_agent)
    @voice_agent = voice_agent
  end

  def payload
    tool_config = VoiceAgents::Config.new(voice_agent.tools_config)
    normalized_tools_config = tool_config.normalized_config
    visible_tool_keys = tool_availability.available_keys(VoiceAgents::ToolRegistry.available_definitions)
    normalized_tools_config[VoiceAgents::Config::ENABLED_KEY] &= visible_tool_keys

    base_attributes.merge(
      config: voice_agent.runtime_config,
      instructions: voice_agent.instructions,
      tools_config: normalized_tools_config,
      enabled_tool_keys: tool_config.enabled_tool_keys & visible_tool_keys,
      knowledge_source_ids: voice_agent.knowledge_sources.map(&:id).sort,
      available_tools: available_tools,
      inbox_settings: inbox_settings,
      ikas_integration: ikas_integration
    ).merge(lifecycle_attributes)
  end

  private

  attr_reader :voice_agent

  def base_attributes
    voice_agent.attributes.slice(*BASE_ATTRIBUTES).symbolize_keys
  end

  def lifecycle_attributes
    {
      lifecycle_status: voice_agent.lifecycle_status,
      published_at: voice_agent.published_at,
      published_revision: voice_agent.published_revision,
      draft_changes: voice_agent.draft_changes?,
      current_release: current_release_payload,
      last_tested_at: voice_agent.last_tested_at,
      readiness: voice_agent.readiness
    }
  end

  def current_release_payload
    return unless voice_agent.current_release

    AssistantReleases::Serializer.new(voice_agent.current_release).payload
  end

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
