FactoryBot.define do
  factory :ai_agent_evaluation_run do
    account
    ai_agent { association :ai_agent, account: account }
    status { :pending }
    prompt_snapshot { ai_agent.prompt }
    config_snapshot { {} }
    draft_fingerprint { ai_agent.draft_fingerprint }
    total_count { 1 }

    trait :completed do
      status { :completed }
      completed_at { Time.current }
    end
  end
end
