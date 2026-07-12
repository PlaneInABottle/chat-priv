FactoryBot.define do
  factory :ai_knowledge_source do
    account
    sequence(:name) { |index| "Knowledge source #{index}" }
    source_type { 'manual' }
    content { 'Verified business information for customer conversations.' }
  end
end
