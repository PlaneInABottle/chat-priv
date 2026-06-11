FactoryBot.define do
  factory :voice_inbox_setting do
    account
    inbox { association :inbox, account: account }
    status { 'test_only' }
    recording_enabled { false }
    settings { {} }
  end
end
