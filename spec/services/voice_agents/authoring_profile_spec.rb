require 'rails_helper'

RSpec.describe VoiceAgents::AuthoringProfile do
  describe '.normalize' do
    it 'normalizes malformed fields independently' do
      profile = described_class.normalize(
        'tone' => 'unsupported',
        'business_context' => 'Valid context',
        'boundaries' => 123
      )

      expect(profile).to eq(
        'tone' => 'friendly',
        'business_context' => 'Valid context',
        'boundaries' => ''
      )
    end

    it 'returns defaults for malformed profile storage and oversized text' do
      expect(described_class.normalize(nil)).to eq(described_class::DEFAULTS)
      expect(described_class.normalize('business_context' => 'x' * 2001)).to eq(described_class::DEFAULTS)
    end
  end

  describe '.merge' do
    it 'strictly validates supplied fields and supports partial merges' do
      current = { 'tone' => 'friendly', 'business_context' => 'Keep me', 'boundaries' => '' }

      expect(described_class.merge(current, tone: 'concise')).to eq(
        'tone' => 'concise', 'business_context' => 'Keep me', 'boundaries' => ''
      )
      expect { described_class.merge(current, tone: 'invalid') }.to raise_error(ArgumentError, /tone is invalid/)
      expect { described_class.merge(current, boundaries: nil) }.to raise_error(ArgumentError, /must be a string/)
      expect { described_class.merge(current, business_context: 'x' * 2001) }.to raise_error(ArgumentError, /too long/)
      expect { described_class.merge(current, []) }.to raise_error(ArgumentError, /must be an object/)
    end
  end
end
