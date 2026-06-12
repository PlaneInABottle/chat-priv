# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/ikas_catalog_mvp'

RSpec.describe IkasCatalogMvp::FacetKeyClassifier do
  describe '.color?' do
    it 'recognizes common color key forms used by Ikas sellers' do
      expect(described_class.color?('Renk')).to be(true)
      expect(described_class.color?('Perde Rengi')).to be(true)
      expect(described_class.color?('Color')).to be(true)
    end

    it 'does not classify unrelated keys as color keys' do
      expect(described_class.color?('Minimum Ölçü Değeri')).to be(false)
      expect(described_class.color?('Ranking')).to be(false)
    end
  end

  describe '.size?' do
    it 'recognizes common size key forms used by Ikas sellers' do
      expect(described_class.size?('Beden')).to be(true)
      expect(described_class.size?('Size')).to be(true)
      expect(described_class.size?('Beden Seçimi')).to be(true)
    end
  end
end
