# frozen_string_literal: true

class AiAgents::Settings
  GLOBAL_INSTRUCTIONS_KEY = 'AI_AGENT_GLOBAL_INSTRUCTIONS'
  LLM_API_KEY_KEY = 'AI_AGENT_LLM_API_KEY'
  LLM_ENDPOINT_KEY = 'AI_AGENT_LLM_ENDPOINT'
  RESPONSE_LIMIT_PER_WINDOW_KEY = 'AI_AGENT_RESPONSE_LIMIT_PER_WINDOW'
  LEGACY_LLM_API_KEY_KEY = 'CAPTAIN_OPEN_AI_API_KEY'
  LEGACY_LLM_ENDPOINT_KEY = 'CAPTAIN_OPEN_AI_ENDPOINT'
  DEFAULT_LLM_ENDPOINT = 'https://openrouter.ai/api/v1/chat/completions'
  DEFAULT_RESPONSE_LIMIT_PER_WINDOW = 50

  class << self
    def global_instructions
      config_value(GLOBAL_INSTRUCTIONS_KEY).to_s.presence
    end

    def llm_api_key
      config_value(LLM_API_KEY_KEY).presence ||
        ENV.fetch(LLM_API_KEY_KEY, nil).presence ||
        ENV.fetch('AI_AGENTS_SIMULATOR_API_KEY', nil).presence ||
        config_value(LEGACY_LLM_API_KEY_KEY).presence ||
        ''
    end

    def llm_endpoint
      config_value(LLM_ENDPOINT_KEY).presence ||
        ENV.fetch(LLM_ENDPOINT_KEY, nil).presence ||
        ENV.fetch('AI_AGENTS_SIMULATOR_ENDPOINT', nil).presence ||
        config_value(LEGACY_LLM_ENDPOINT_KEY).presence ||
        DEFAULT_LLM_ENDPOINT
    end

    def llm_timeout_seconds
      ENV.fetch('AI_AGENTS_SIMULATOR_TIMEOUT_SECONDS', '20').to_i
    end

    # Returns the global AI response limit per 24h window.
    # Explicit 0 disables the limit; nil/negative/garbage values fall back to the
    # hard default so malformed configuration can never accidentally mean unlimited.
    def response_limit_per_window
      value = Integer(config_value(RESPONSE_LIMIT_PER_WINDOW_KEY), exception: false)
      return 0 if value&.zero?
      return value if value&.positive?

      DEFAULT_RESPONSE_LIMIT_PER_WINDOW
    end

    private

    def config_value(key)
      GlobalConfig.get_value(key)
    end
  end
end
