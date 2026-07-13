FactoryBot.define do
  factory :ai_agent_evaluation_generation do
    account
    ai_agent { association :ai_agent, account: account }
    initiated_by { association :user, account: account }
    status { :pending }
    requested_count { 5 }
    created_count { 0 }
  end
end
