# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join('db/migrate/20260628000000_align_fork_feature_flags_with_upstream')

# rubocop:disable RSpec/SpecFilePathFormat
RSpec.describe AlignForkFeatureFlagsWithUpstream do
  let!(:account) { create(:account) }

  it 'preserves pre-sync feature meanings while moving Ikas to extension slot 6' do
    old_unsigned_flags = (1 << 0) | (1 << 41) | (1 << 42) | (1 << 63)
    old_signed_flags = old_unsigned_flags - (1 << 64)
    # Raw bit patterns are required to exercise the migration boundary.
    # rubocop:disable Rails/SkipsModelValidations
    account.update_columns(feature_flags: old_signed_flags, feature_flags_ext_1: 1)
    # rubocop:enable Rails/SkipsModelValidations

    described_class.new.up

    account.reload
    expect(account.feature_flags).to eq((1 << 0) | (1 << 41) | (1 << 62))
    expect(account.feature_flags_ext_1).to eq(1 | (1 << 5))
  end

  it 'restores the pre-sync bit layout on rollback' do
    # rubocop:disable Rails/SkipsModelValidations
    account.update_columns(
      feature_flags: (1 << 0) | (1 << 41) | (1 << 62),
      feature_flags_ext_1: 1 | (1 << 5)
    )
    # rubocop:enable Rails/SkipsModelValidations

    described_class.new.down

    account.reload
    restored_unsigned_flags = account.feature_flags & ((1 << 64) - 1)
    expect(restored_unsigned_flags).to eq((1 << 0) | (1 << 41) | (1 << 42) | (1 << 63))
    expect(account.feature_flags_ext_1).to eq(1)
  end

  it 'runs before upstream repurposes the shifted quoted-email flag' do
    migration_versions = Dir[Rails.root.join('db/migrate/*.rb')].to_h do |path|
      [File.basename(path).delete_suffix('.rb').split('_', 2).last, File.basename(path).to_i]
    end

    alignment_version = migration_versions.fetch('align_fork_feature_flags_with_upstream')
    repurpose_version = migration_versions.fetch('repurpose_quoted_email_reply_flag_for_unread_count_for_filters')

    expect(alignment_version).to be < repurpose_version
  end
end
# rubocop:enable RSpec/SpecFilePathFormat
