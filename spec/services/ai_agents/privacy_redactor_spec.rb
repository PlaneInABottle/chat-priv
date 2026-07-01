require 'rails_helper'

RSpec.describe AiAgents::PrivacyRedactor do
  it 'redacts email and phone values from free text' do
    text = 'Email test@example.com telefon +90 555 123 45 67 siparis TEST-12345'

    expect(described_class.redact_text(text)).to eq('Email [email redacted] telefon [phone redacted] siparis TEST-12345')
  end

  it 'masks email and phone values for logs' do
    expect(described_class.mask_email('test@example.com')).to eq('t***@example.com')
    expect(described_class.mask_phone('+90 555 123 45 67')).to eq('***4567')
  end
end
