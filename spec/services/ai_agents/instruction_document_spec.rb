require 'rails_helper'

RSpec.describe AiAgents::InstructionDocument do
  describe '#normalized' do
    it 'normalizes profile values and keeps supported sections' do
      document = described_class.new(
        'profile' => { 'language' => 'tr', 'tone' => 'friendly', 'formality' => 'invalid' },
        'sections' => [
          { 'key' => 'identity', 'content' => 'Help customers.', 'critical' => true },
          { 'key' => 'custom_returns', 'title' => 'Returns', 'content' => 'Explain the return policy.', 'custom' => true }
        ]
      ).normalized

      expect(document.dig('profile', 'language')).to eq('tr')
      expect(document.dig('profile', 'formality')).to eq('balanced')
      expect(document['sections']).to contain_exactly(
        include('key' => 'identity', 'title' => 'Identity and purpose', 'critical' => true),
        include('key' => 'custom_returns', 'title' => 'Returns', 'custom' => true)
      )
    end
  end

  describe '#compile' do
    it 'compiles profile controls, section headings, rich content, and critical priority' do
      prompt = described_class.new(
        'profile' => { 'language' => 'tr', 'tone' => 'professional', 'response_length' => 'short' },
        'sections' => [
          { 'key' => 'rules', 'content' => '<ul><li>Never invent prices.</li></ul>', 'critical' => true }
        ]
      ).compile

      expect(prompt).to include('Reply language: Turkish', 'Tone: Professional', 'Response length: Short')
      expect(prompt).to include('## Rules and boundaries — CRITICAL, must always be followed')
      expect(prompt).to include('<ul><li>Never invent prices.</li></ul>')
    end
  end

  describe '.from_legacy' do
    it 'preserves the existing prompt in one editable section' do
      document = described_class.from_legacy('Existing instructions')

      expect(document['sections']).to contain_exactly(
        include('key' => 'current_instructions', 'content' => 'Existing instructions')
      )
    end
  end
end
