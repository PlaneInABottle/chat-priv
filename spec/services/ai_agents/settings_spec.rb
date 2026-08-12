# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgents::Settings do
  describe '.global_instructions' do
    it 'returns configured platform instructions' do
      upsert_config('AI_AGENT_GLOBAL_INSTRUCTIONS', 'Use verified evidence.')

      expect(described_class.global_instructions).to eq('Use verified evidence.')
    end
  end

  describe '.llm_api_key' do
    it 'prefers AI Agent config over environment and legacy Captain config' do
      upsert_config('AI_AGENT_LLM_API_KEY', 'ai-agent-key')
      upsert_config('CAPTAIN_OPEN_AI_API_KEY', 'captain-key')

      with_modified_env AI_AGENT_LLM_API_KEY: 'env-key' do
        expect(described_class.llm_api_key).to eq('ai-agent-key')
      end
    end

    it 'uses the AI Agent environment fallback before legacy Captain config' do
      upsert_config('AI_AGENT_LLM_API_KEY', nil)
      upsert_config('CAPTAIN_OPEN_AI_API_KEY', 'captain-key')

      with_modified_env AI_AGENT_LLM_API_KEY: 'env-key' do
        expect(described_class.llm_api_key).to eq('env-key')
      end
    end

    it 'keeps the old simulator environment fallback for local development compatibility' do
      upsert_config('AI_AGENT_LLM_API_KEY', nil)
      upsert_config('CAPTAIN_OPEN_AI_API_KEY', 'captain-key')

      with_modified_env AI_AGENT_LLM_API_KEY: nil, AI_AGENTS_SIMULATOR_API_KEY: 'simulator-key' do
        expect(described_class.llm_api_key).to eq('simulator-key')
      end
    end
  end

  describe '.llm_endpoint' do
    it 'defaults to OpenRouter chat completions' do
      expect(described_class.llm_endpoint).to eq('https://openrouter.ai/api/v1/chat/completions')
    end

    it 'uses the AI Agent environment fallback before the default endpoint' do
      upsert_config('AI_AGENT_LLM_ENDPOINT', nil)

      with_modified_env AI_AGENT_LLM_ENDPOINT: 'https://llm.example.test/v1/chat/completions' do
        expect(described_class.llm_endpoint).to eq('https://llm.example.test/v1/chat/completions')
      end
    end
  end

  describe '.response_limit_per_window' do
    it 'returns 50 when no config row exists' do
      expect(described_class.response_limit_per_window).to eq(50)
    end

    it 'returns the configured value when it is a positive integer' do
      upsert_config('AI_AGENT_RESPONSE_LIMIT_PER_WINDOW', 50)

      expect(described_class.response_limit_per_window).to eq(50)
    end

    it 'returns 0 for an explicit zero (unlimited)' do
      upsert_config('AI_AGENT_RESPONSE_LIMIT_PER_WINDOW', 0)

      expect(described_class.response_limit_per_window).to eq(0)
    end

    it 'returns 0 for a stringified zero' do
      upsert_config('AI_AGENT_RESPONSE_LIMIT_PER_WINDOW', '0')

      expect(described_class.response_limit_per_window).to eq(0)
    end

    it 'falls back to 50 for negative values' do
      upsert_config('AI_AGENT_RESPONSE_LIMIT_PER_WINDOW', -5)

      expect(described_class.response_limit_per_window).to eq(50)
    end

    it 'falls back to 50 for non-integer garbage' do
      upsert_config('AI_AGENT_RESPONSE_LIMIT_PER_WINDOW', 'abc')

      expect(described_class.response_limit_per_window).to eq(50)
    end
  end

  def upsert_config(name, value)
    InstallationConfig.where(name: name).first_or_initialize.tap do |config|
      config.value = value
      config.locked = false
      config.save!
    end
  end
end
