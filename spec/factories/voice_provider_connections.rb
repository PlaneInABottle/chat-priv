FactoryBot.define do
  factory :voice_provider_connection do
    account
    sequence(:name) { |n| "Test SIP #{n}" }
    provider { 'test_sip' }
    status { 'active' }
    settings { {} }
  end
end
