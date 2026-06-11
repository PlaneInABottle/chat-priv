require 'rails_helper'

RSpec.describe VoiceAgents::PromptComposer do
  describe '#effective_system_prompt' do
    it 'combines installation branding, global instructions, voice prompt, and tool policy' do
      voice_agent = build(
        :voice_agent,
        greeting: 'Merhaba',
        prompt: 'Sadece kisa cevap ver.',
        language: 'tr',
        tools_config: VoiceAgents::Config.new(
          'enabled' => %w[human_handoff ikas_catalog_search]
        ).normalized_config
      )
      allow(GlobalConfigService).to receive(:load).with('INSTALLATION_NAME', 'Kozmopath').and_return('Acme Support')
      allow(AiAgents::Settings).to receive(:global_instructions).and_return('Never invent facts.')

      prompt = described_class.new(voice_agent: voice_agent).effective_system_prompt

      expect(prompt).to include("You are Acme Support's customer support voice assistant.")
      expect(prompt).to include('Platform global AI instructions:')
      expect(prompt).to include('Never invent facts.')
      expect(prompt).to include('Voice language: tr')
      expect(prompt).to include('Preferred greeting: Merhaba')
      expect(prompt).to include('Voice agent instructions:')
      expect(prompt).to include('Sadece kisa cevap ver.')
      expect(prompt).to include('Use `ikas_catalog_search` before answering questions about products')
      expect(prompt).to include('Voice product-link rule:')
    end
  end
end
