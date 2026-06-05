# frozen_string_literal: true

class AiAgents::PrivacyRedactor
  EMAIL_REGEX = /\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i
  PHONE_REGEX = /(?<!\d)\+?\d[\d\s().-]{7,}\d(?!\d)/

  def self.redact_text(value)
    value.to_s
         .gsub(EMAIL_REGEX, '[email redacted]')
         .gsub(PHONE_REGEX, '[phone redacted]')
  end

  def self.mask_email(value)
    local, domain = value.to_s.split('@', 2)
    return '[redacted]' if local.blank? || domain.blank?

    "#{local.first}***@#{domain}"
  end

  def self.mask_phone(value)
    digits = value.to_s.delete('^0-9')
    return '[redacted]' if digits.length < 4

    "***#{digits.last(4)}"
  end
end
