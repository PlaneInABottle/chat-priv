require 'rails_helper'

RSpec.describe VoiceAgents::PromptComposer do
  describe '#effective_system_prompt' do
    it 'combines installation branding, global instructions, voice prompt, and tool policy', :aggregate_failures do
      voice_agent = build(
        :voice_agent,
        greeting: 'Merhaba',
        prompt: 'Sadece kisa cevap ver.',
        language: 'tr',
        tools_config: VoiceAgents::Config.new(
          'enabled' => %w[human_handoff ikas_catalog_search ikas_lookup_order]
        ).normalized_config
      )
      allow(GlobalConfigService).to receive(:load).with('INSTALLATION_NAME', 'Chatwoot').and_return('Acme Support')
      allow(AiAgents::Settings).to receive(:global_instructions).and_return('Never invent facts.')

      prompt = described_class.new(voice_agent: voice_agent).effective_system_prompt

      expect(prompt).to include("You are Acme Support's customer support voice assistant.")
      expect(prompt).to include('Treat unclear or multilingual-looking speech as possible speech-to-text noise.')
      expect(prompt).to include('prefer a plausible Turkish interpretation')
      expect(prompt).to include('# Role and Objective')
      expect(prompt).to include('# Platform Rules')
      expect(prompt).to include('Never invent facts.')
      expect(prompt).to include("# Language\nVoice language: tr")
      expect(prompt).to include("# Greeting\nPreferred greeting: Merhaba")
      expect(prompt).to include('# Customer Instructions')
      expect(prompt).to include('Sadece kisa cevap ver.')
      expect(prompt).to include('# Tools')
      expect(prompt).to include('Use `ikas_catalog_search` before answering questions about products')
      expect(prompt).to include('Use `ikas_lookup_order` before answering questions about order status')
      expect(prompt).to include('Never reveal or repeat customer email, phone, billing address, shipping address')
      expect(prompt).to include('Voice product-link rule:')
    end
  end
end
