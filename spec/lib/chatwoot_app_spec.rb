# frozen_string_literal: true

require 'rails_helper'
require 'tmpdir'
require 'fileutils'

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
        # FOSS CI strips the repository `enterprise/` directory, so the check must
        # run against a self-contained root that always provides the directory.
        Dir.mktmpdir do |dir|
          FileUtils.mkdir_p(File.join(dir, 'enterprise'))
          allow(described_class).to receive(:root).and_return(Pathname.new(dir))

          with_modified_env DISABLE_ENTERPRISE: disable_enterprise do
            expect(described_class.enterprise?).to eq(expected)
          end
        end
      end
    end
  end
end
