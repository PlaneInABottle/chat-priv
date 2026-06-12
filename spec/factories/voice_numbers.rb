FactoryBot.define do
  sequence(:voice_phone_number) { |n| "+90555#{Process.pid.to_s.last(3).rjust(3, '0')}#{n.to_s.rjust(4, '0')}" }

  factory :voice_number do
    account
    voice_provider_connection { association :voice_provider_connection, account: account }
    voice_inbox_setting { association :voice_inbox_setting, account: account }
    phone_number { generate(:voice_phone_number) }
    status { 'active' }
    settings { {} }
  end
end
