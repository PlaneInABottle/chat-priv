require 'rails_helper'

RSpec.describe VoiceNumber do
  it { is_expected.to belong_to(:account) }
  it { is_expected.to belong_to(:voice_provider_connection) }
  it { is_expected.to belong_to(:voice_inbox_setting) }

  it 'normalizes phone numbers before validation' do
    number = create(:voice_number, phone_number: '+90 (555) 123-4567')

    expect(number.phone_number).to eq('+905551234567')
  end

  it 'normalizes dialed number lookups' do
    number = create(:voice_number, phone_number: '+90 (555) 123-4567')

    expect(described_class.for_dialed_number('+90 555 123 4567')).to contain_exactly(number)
    expect(described_class.for_dialed_number(nil)).to be_empty
  end

  it 'rejects provider connections from another account' do
    number = build(:voice_number, voice_provider_connection: create(:voice_provider_connection))

    expect(number).not_to be_valid
    expect(number.errors[:voice_provider_connection_id]).to include('must belong to account')
  end

  it 'rejects voice inbox settings from another account' do
    number = build(:voice_number, voice_inbox_setting: create(:voice_inbox_setting))

    expect(number).not_to be_valid
    expect(number.errors[:voice_inbox_setting_id]).to include('must belong to account')
  end
end
