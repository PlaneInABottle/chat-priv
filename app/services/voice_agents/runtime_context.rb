# frozen_string_literal: true

class VoiceAgents::RuntimeContext
  def initialize(call:)
    @call = call
  end

  def payload
    {
      call: call_payload,
      voice_agent: voice_agent_payload,
      instructions: VoiceAgents::PromptComposer.new(voice_agent: voice_agent).effective_system_prompt,
      tools: tool_payloads,
      runtime: runtime_payload
    }
  end

  private

  attr_reader :call

  def call_payload
    {
      id: call.id,
      account_id: call.account_id,
      inbox_id: call.inbox_id,
      provider_call_id: call.provider_call_id,
      livekit_room_name: call.livekit_room_name,
      test_call: call.test_call?,
      voice_number_id: call.meta&.fetch('voice_number_id', nil),
      voice_provider_connection_id: call.meta&.fetch('voice_provider_connection_id', nil)
    }
  end

  def voice_agent_payload
    {
      id: voice_agent.id,
      name: voice_agent.name,
      enabled: voice_agent.enabled,
      greeting: voice_agent.greeting,
      architecture: voice_agent.architecture,
      provider: voice_agent.provider,
      model: voice_agent.model,
      voice: voice_agent.voice,
      language: voice_agent.language
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
      architecture: voice_agent.architecture,
      provider: voice_agent.provider,
      model: voice_agent.model,
      voice: voice_agent.voice,
      language: voice_agent.language,
      config: voice_agent.config
    }
  end

  def enabled_tool_keys
    @enabled_tool_keys ||= VoiceAgents::Config.new(voice_agent.tools_config).enabled_tool_keys
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
end
