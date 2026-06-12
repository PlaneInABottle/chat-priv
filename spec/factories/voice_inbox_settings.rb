FactoryBot.define do
  factory :voice_inbox_setting do
    account
    inbox { association :inbox, account: account }
    recording_enabled { false }
    settings { {} }
  end
end
