FactoryBot.define do
  factory :ai_agent_evaluation_case do
    account
    ai_agent { association :ai_agent, account: account }
    sequence(:name) { |number| "Evaluation scenario #{number}" }
    customer_message { 'When will my order arrive?' }
    success_criteria { 'Do not promise an exact delivery date.' }
    position { 1 }
  end
end
