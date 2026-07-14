FactoryBot.define do
  factory :ai_agent_website_import do
    account
    ai_agent { association :ai_agent, account: account }
    requested_by { association :user, account: account }
    website_url { 'https://example.com/' }
    status { :pending }
    stage { :queued }
    base_draft_fingerprint { ai_agent.draft_fingerprint }
    base_document do
      instructions = ai_agent.config.to_h['instructions']
      instructions.presence || AiAgents::InstructionDocument.from_legacy(ai_agent.prompt)
    end

    trait :ready do
      status { :ready }
      stage { :complete }
      proposed_sections { { 'business_context' => 'Example sells support software.' } }
      completed_at { Time.current }
    end
  end
end
