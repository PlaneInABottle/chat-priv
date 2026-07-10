require 'rails_helper'

RSpec.describe AiAgents::InstructionDocument do
  describe '#normalized' do
    it 'keeps fixed sections and normalizes optional profile values' do
      document = described_class.new(
        'profile' => { 'language' => 'tr', 'tone' => 'friendly', 'formality' => 'invalid' },
        'sections' => { 'rules' => 'Never invent prices.', 'unknown' => 'Ignored' }
      ).normalized

      expect(document).to include('version' => 3)
      expect(document.dig('profile', 'language')).to eq('tr')
      expect(document.dig('profile', 'formality')).to eq('not_set')
      expect(document.dig('sections', 'rules')).to eq('Never invent prices.')
      expect(document['sections']).not_to have_key('unknown')
    end

    it 'converts version one sections without preserving fake priority metadata' do
      document = described_class.new(
        'version' => 1,
        'sections' => [
          { 'key' => 'rules', 'content' => '<p>Never invent prices.</p>', 'critical' => true }
        ]
      ).normalized

      expect(document.dig('sections', 'rules')).to eq('Never invent prices.')
      expect(document.to_s).not_to include('critical')
    end

    it 'splits known Markdown headings and preserves unknown content under additional instructions' do
      document = described_class.new(
        'version' => 2,
        'content' => <<~MARKDOWN
          Keep this preamble.

          ## Identity and purpose

          Help customers.

          ## Store-specific guidance

          Preserve **this** block.
        MARKDOWN
      ).normalized

      expect(document.dig('sections', 'identity')).to eq('Help customers.')
      expect(document.dig('sections', 'additional')).to include(
        'Keep this preamble.',
        '## Store-specific guidance',
        'Preserve **this** block.'
      )
    end

    it 'concatenates duplicate known Markdown sections' do
      document = described_class.new(
        'version' => 2,
        'content' => "## Rules and boundaries\n\nFirst rule.\n\n## Rules and boundaries\n\nSecond rule."
      ).normalized

      expect(document.dig('sections', 'rules')).to eq("First rule.\n\nSecond rule.")
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
        'sections' => {
          'identity' => '',
          'rules' => '- Never invent prices.'
        }
      ).compile

      expect(prompt).to include('Reply language: Turkish', 'Tone: Professional', 'Response length: Short')
      expect(prompt).not_to include('Formality:', 'CRITICAL')
      expect(prompt).to include("## Rules and boundaries\n\n- Never invent prices.")
      expect(prompt).not_to include('## Identity and purpose')
    end
  end

  describe '.from_legacy' do
    it 'preserves the existing prompt under additional instructions' do
      document = described_class.from_legacy("Existing <rules>\nSecond line")

      expect(document).to include('version' => 3)
      expect(document['profile'].values).to all(eq('not_set'))
      expect(document.dig('sections', 'additional')).to eq("Existing <rules>\nSecond line")
    end
  end
end
