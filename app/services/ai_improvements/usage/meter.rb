# frozen_string_literal: true

class AiImprovements::Usage::Meter
  UNITS_PER_CREDIT = {
    'tokens' => 1_000,
    'embedding_tokens' => 1_000,
    'audio_seconds' => 10
  }.freeze

  def self.credits_for(unit_type:, units:)
    divisor = UNITS_PER_CREDIT.fetch(unit_type.to_s)
    normalized_units = [units.to_f, 0].max
    [normalized_units.fdiv(divisor).ceil, 1].max
  end
end
