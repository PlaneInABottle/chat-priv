# frozen_string_literal: true

class VoiceAgents::RuntimeContext
  def initialize(call:)
    @call = call
  end

  def payload
    {
      call: call_payload,
      voice_agent: voice_agent_payload,
      instructions: VoiceAgents::PromptComposer.new(voice_agent: voice_agent, snapshot: runtime_snapshot).effective_system_prompt,
      tools: tool_payloads,
      runtime: runtime_payload
    }
  end

  private

  attr_reader :call

  def call_payload
    base_call_payload.merge(release_call_payload)
  end

  def base_call_payload
    {
      id: call.id,
      account_id: call.account_id,
      inbox_id: call.inbox_id,
      provider_call_id: call.provider_call_id,
      livekit_room_name: call.livekit_room_name,
      test_call: call.test_call?,
      test_duration_limit_seconds: test_duration_limit_seconds,
      voice_number_id: call.meta&.fetch('voice_number_id', nil),
      voice_provider_connection_id: call.meta&.fetch('voice_provider_connection_id', nil)
    }
  end

  def release_call_payload
    {
      voice_agent_release_id: resolved_release&.id,
      voice_agent_revision: resolved_release&.revision,
      draft_fingerprint: call.test_call? ? voice_agent.draft_fingerprint : nil
    }
  end

  def test_duration_limit_seconds
    duration_limit = call.meta.to_h['ai_improvement_max_duration_seconds'].to_i
    return unless call.test_call? && duration_limit.positive?

    duration_limit
  end

  def voice_agent_payload
    {
      id: voice_agent.id,
      name: voice_agent.name,
      enabled: voice_agent.enabled,
      greeting: runtime_value(:greeting),
      architecture: runtime_value(:architecture),
      provider: runtime_value(:provider),
      model: runtime_value(:model),
      voice: runtime_value(:voice),
      language: runtime_value(:language),
      release_id: resolved_release&.id,
      revision: resolved_release&.revision
    }
  end

  def tool_payloads
    enabled_tool_keys.filter_map do |tool_key|
      definition = VoiceAgents::ToolRegistry.find(tool_key)
      next unless definition

      {
        key: definition.key,
        name: definition.name,
        description: definition.description,
        input_schema: definition.input_schema,
        terminal: definition.terminal
      }
    end
  end

  def runtime_payload
    {
      architecture: runtime_value(:architecture),
      provider: runtime_value(:provider),
      model: runtime_value(:model),
      voice: runtime_value(:voice),
      language: runtime_value(:language),
      config: runtime_value(:config)
    }
  end

  def enabled_tool_keys
    @enabled_tool_keys ||= begin
      keys = VoiceAgents::Config.new(runtime_value(:tools_config)).enabled_tool_keys
      keys = [*keys, VoiceAgents::Config::KNOWLEDGE_SEARCH_TOOL] if runtime_knowledge_sources.present?
      keys
    end
  end

  def runtime_knowledge_sources
    @runtime_knowledge_sources ||= Array(runtime_value(:knowledge_sources))
  end

  def voice_agent
    @voice_agent ||= begin
      agent = setting&.voice_agent || call.account.voice_agents.find_by(id: call.meta&.fetch('voice_agent_id', nil))
      raise ActiveRecord::RecordNotFound, 'Voice agent not configured' unless agent

      agent
    end
  end

  def setting
    @setting ||= call.account.voice_inbox_setting_for(
      inbox: call.inbox,
      id: call.meta&.fetch('voice_inbox_setting_id', nil)
    )
  end

  def runtime_snapshot
    @runtime_snapshot ||= resolved_release&.snapshot&.deep_stringify_keys || VoiceAgents::ReleaseSnapshot.for(voice_agent)
  end

  def runtime_value(key)
    runtime_snapshot[key.to_s]
  end

  def resolved_release
    return if call.test_call?
    return @resolved_release if defined?(@resolved_release)

    @resolved_release = call.voice_agent_release || voice_agent.current_release
    call.update!(voice_agent_release: @resolved_release) if @resolved_release && call.voice_agent_release_id != @resolved_release.id
    @resolved_release
  end
end
