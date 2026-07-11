# frozen_string_literal: true

class VoiceAgents::RuntimeDefaults
  def self.attributes
    provider = ENV.fetch('VOICE_AGENT_DEFAULT_REALTIME_PROVIDER', 'gemini')

    {
      architecture: 'realtime',
      provider: provider,
      model: default_model(provider),
      voice: default_voice(provider),
      language: ENV.fetch('VOICE_AGENT_DEFAULT_LANGUAGE', 'tr')
    }
  end

  def self.default_model(provider)
    return ENV.fetch('VOICE_AGENT_DEFAULT_OPENAI_MODEL', VoiceAgent::OPENAI_REALTIME_MODELS.first) if provider == 'openai'

    ENV['VOICE_AGENT_DEFAULT_GEMINI_MODEL'].presence
  end

  def self.default_voice(provider)
    return ENV.fetch('VOICE_AGENT_DEFAULT_OPENAI_VOICE', 'marin') if provider == 'openai'

    ENV.fetch('VOICE_AGENT_DEFAULT_GEMINI_VOICE', 'Charon')
  end

  private_class_method :default_model, :default_voice
end
