require 'rails_helper'

RSpec.describe VoiceAgents::RuntimeDefaults do
  describe '.attributes' do
    it 'keeps Gemini defaults until the deployment enables OpenAI' do
      with_modified_env VOICE_AGENT_DEFAULT_REALTIME_PROVIDER: nil do
        expect(described_class.attributes).to include(
          architecture: 'realtime',
          provider: 'gemini',
          model: nil,
          voice: 'Charon',
          language: 'tr'
        )
      end
    end

    it 'provides a complete OpenAI realtime runtime' do
      with_modified_env VOICE_AGENT_DEFAULT_REALTIME_PROVIDER: 'openai' do
        expect(described_class.attributes).to include(
          architecture: 'realtime',
          provider: 'openai',
          model: 'gpt-realtime-2.1',
          voice: 'marin',
          language: 'tr'
        )
      end
    end
  end
end
