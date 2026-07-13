# frozen_string_literal: true

class AiDataRetention::Policy
  DEFAULT_DAYS = 30
  ALLOWED_DAYS = [7, 30, 90, 180, 365].freeze
  KINDS = %w[text voice].freeze

  def self.normalize_days(value)
    days = value.to_i
    ALLOWED_DAYS.include?(days) ? days : DEFAULT_DAYS
  end

  def self.valid_days?(value)
    ALLOWED_DAYS.include?(value.to_i)
  end

  def self.valid_kind?(value)
    KINDS.include?(value.to_s)
  end
end
