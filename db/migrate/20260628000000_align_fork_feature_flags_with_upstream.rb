class AlignForkFeatureFlagsWithUpstream < ActiveRecord::Migration[7.1]
  # The source positions are the final pre-sync `develop` mapping: Ikas was at
  # position 42 and the remaining flags occupied positions 43 through 64.
  # Upstream uses all 63 safe bigint positions, so Ikas moves to ext_1 slot 6
  # while the trailing flags shift down one position without changing meaning.
  LOW_FEATURE_MASK = (1 << 41) - 1
  TRAILING_FEATURE_MASK = (1 << 22) - 1
  IKAS_SOURCE_SHIFT = 41
  IKAS_TARGET_SHIFT = 5

  def up
    add_column :accounts, :feature_flags_ext_1, :bigint, default: 0, null: false unless column_exists?(:accounts, :feature_flags_ext_1)

    execute <<~SQL.squish
      UPDATE accounts
      SET feature_flags =
            (feature_flags & #{LOW_FEATURE_MASK}) |
            (((feature_flags >> 42) & #{TRAILING_FEATURE_MASK}) << 41),
          feature_flags_ext_1 =
            feature_flags_ext_1 |
            (((feature_flags >> #{IKAS_SOURCE_SHIFT}) & 1) << #{IKAS_TARGET_SHIFT})
    SQL
  end

  def down
    execute <<~SQL.squish
      UPDATE accounts
      SET feature_flags =
            (feature_flags & #{LOW_FEATURE_MASK}) |
            (((feature_flags >> 41) & #{TRAILING_FEATURE_MASK}) << 42) |
            (((feature_flags_ext_1 >> #{IKAS_TARGET_SHIFT}) & 1) << #{IKAS_SOURCE_SHIFT}),
          feature_flags_ext_1 = feature_flags_ext_1 & ~#{1 << IKAS_TARGET_SHIFT}
    SQL
  end
end
