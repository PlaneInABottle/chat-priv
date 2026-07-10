require 'rails_helper'

RSpec.describe AiDataRetention::Policy do
  describe '.normalize_days' do
    it 'keeps supported values and defaults unsupported values' do
      expect(described_class.normalize_days('90')).to eq(90)
      expect(described_class.normalize_days(14)).to eq(30)
      expect(described_class.normalize_days(nil)).to eq(30)
    end
  end

  describe '.valid_kind?' do
    it 'accepts only separate text and voice policies' do
      expect(described_class.valid_kind?('text')).to be(true)
      expect(described_class.valid_kind?('voice')).to be(true)
      expect(described_class.valid_kind?('all')).to be(false)
    end
  end
end
