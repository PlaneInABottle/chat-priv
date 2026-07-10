require 'rails_helper'

RSpec.describe AiAgents::InstructionDocument do
  describe '#normalized' do
    it 'keeps a single Markdown document and normalizes optional profile values' do
      document = described_class.new(
        'profile' => { 'language' => 'tr', 'tone' => 'friendly', 'formality' => 'invalid' },
        'content' => "## Rules\n\nNever invent prices."
      ).normalized

      expect(document).to include('version' => 2)
      expect(document.dig('profile', 'language')).to eq('tr')
      expect(document.dig('profile', 'formality')).to eq('not_set')
      expect(document['content']).to eq("## Rules\n\nNever invent prices.")
    end

    it 'converts version one sections without preserving fake priority metadata' do
      document = described_class.new(
        'version' => 1,
        'sections' => [
          { 'key' => 'rules', 'content' => '<p>Never invent prices.</p>', 'critical' => true }
        ]
      ).normalized

      expect(document['content']).to eq("## Rules and boundaries\n\nNever invent prices.")
      expect(document).not_to have_key('sections')
      expect(document.to_s).not_to include('critical')
    end
  end

  describe '#compile' do
    it 'compiles selected profile controls and rich headings into clean prompt text' do
      prompt = described_class.new(
        'profile' => {
          'language' => 'tr',
          'tone' => 'professional',
          'formality' => 'not_set',
          'response_length' => 'short'
        },
        'content' => "## Rules and boundaries\n\n- Never invent prices."
      ).compile

      expect(prompt).to include('Reply language: Turkish', 'Tone: Professional', 'Response length: Short')
      expect(prompt).not_to include('Formality:', 'CRITICAL')
      expect(prompt).to include("## Rules and boundaries\n\n- Never invent prices.")
    end
  end

  describe '.from_legacy' do
    it 'preserves and escapes the existing prompt in a general instructions document' do
      document = described_class.from_legacy("Existing <rules>\nSecond line")

      expect(document).to include('version' => 2)
      expect(document['profile'].values).to all(eq('not_set'))
      expect(document['content']).to eq("## General instructions\n\nExisting <rules>\nSecond line")
    end
  end
end
