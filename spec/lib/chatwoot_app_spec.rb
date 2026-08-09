# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatwootApp do
  describe '.enterprise?' do
    {
      'true' => false,
      '1' => false,
      't' => false,
      'false' => true,
      '0' => true,
      'f' => true,
      'off' => true,
      nil => true
    }.each do |disable_enterprise, expected|
      it "returns #{expected} when DISABLE_ENTERPRISE is #{disable_enterprise.inspect}" do
        with_modified_env DISABLE_ENTERPRISE: disable_enterprise do
          expect(described_class.enterprise?).to eq(expected)
        end
      end
    end
  end
end
