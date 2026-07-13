FactoryBot.define do
  factory :ai_knowledge_source do
    account
    sequence(:name) { |index| "Knowledge source #{index}" }
    source_type { 'manual' }
    content { 'Verified business information for customer conversations.' }

    trait :website do
      source_type { 'website' }
      website_url { 'https://example.com/' }
      content { '' }
      sync_status { :pending }
    end
  end
end
