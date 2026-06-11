FactoryBot.define do
  factory :voice_recording do
    call
    account { call.account }
    status { 'active' }
    storage_provider { 's3_compatible' }
    sequence(:egress_id) { |n| "EG_#{n}" }
    bucket { 'voice-recordings-test' }
    sequence(:object_key) { |n| "voice-recordings/account-#{account.id}/call-#{call.id}/recording-#{n}.mp4" }
    content_type { 'audio/mp4' }
    started_at { Time.zone.now }
  end
end
