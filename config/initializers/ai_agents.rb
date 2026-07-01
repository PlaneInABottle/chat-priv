# frozen_string_literal: true

require 'agents'

Rails.application.config.after_initialize do
  # Skip AI Agents configuration if database isn't ready (during asset precompile, etc.)
  next unless ActiveRecord::Base.connection.present? && InstallationConfig.table_exists?

  api_key = AiAgents::Settings.llm_api_key
  model = ENV.fetch('AI_AGENT_LLM_MODEL', LlmConstants::DEFAULT_MODEL)
  api_endpoint = AiAgents::Settings.llm_endpoint

  if api_key.present?
    Agents.configure do |config|
      config.openai_api_key = api_key
      if api_endpoint.present?
        api_base = api_endpoint.chomp('/').sub(%r{/chat/completions\z}, '')
        api_base = "#{api_base}/v1" unless api_base.end_with?('/v1')
        config.openai_api_base = api_base
      end
      config.default_model = model
      config.debug = false
    end
  end
rescue StandardError => e
  Rails.logger.error { "Failed to configure AI Agents SDK: #{e.message}" }
end
