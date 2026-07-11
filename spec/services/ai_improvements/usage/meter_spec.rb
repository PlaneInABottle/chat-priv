require 'rails_helper'

RSpec.describe AiImprovements::Usage::Meter do
  describe '.credits_for' do
    it 'charges one credit per started thousand text tokens' do
      expect(described_class.credits_for(unit_type: 'tokens', units: 0)).to eq(1)
      expect(described_class.credits_for(unit_type: 'tokens', units: 1_000)).to eq(1)
      expect(described_class.credits_for(unit_type: 'tokens', units: 1_001)).to eq(2)
    end

    it 'charges one credit per started thousand embedding tokens' do
      expect(described_class.credits_for(unit_type: 'embedding_tokens', units: 2_001)).to eq(3)
    end

    it 'charges one credit per started ten seconds of test audio' do
      expect(described_class.credits_for(unit_type: 'audio_seconds', units: 10)).to eq(1)
      expect(described_class.credits_for(unit_type: 'audio_seconds', units: 11)).to eq(2)
    end

    it 'rejects unknown unit types' do
      expect do
        described_class.credits_for(unit_type: 'requests', units: 1)
      end.to raise_error(KeyError)
    end
  end
end
