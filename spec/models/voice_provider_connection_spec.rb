require 'rails_helper'

RSpec.describe VoiceProviderConnection do
  it { is_expected.to belong_to(:account) }
  it { is_expected.to have_many(:voice_numbers).dependent(:destroy) }

  it 'validates provider and status' do
    connection = build(:voice_provider_connection, provider: 'twilio_magic', status: 'unknown')

    expect(connection).not_to be_valid
    expect(connection.errors[:provider]).to be_present
    expect(connection.errors[:status]).to be_present
  end
end
