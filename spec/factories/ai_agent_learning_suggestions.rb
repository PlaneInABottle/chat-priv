FactoryBot.define do
  factory :ai_agent_learning_suggestion do
    account
    ai_agent { association :ai_agent, account: account }
    conversation { association :conversation, account: account }
    source_message do
      association :message,
                  account: account,
                  conversation: conversation,
                  inbox: conversation.inbox
    end
    submitted_by { association :user, account: account }
    status { :pending }
    customer_message { 'When will my order arrive?' }
    human_answer { 'Delivery time depends on the destination.' }

    trait :ready do
      status { :ready }
      destination { 'instructions' }
      target_section { 'rules' }
      suggested_instruction { 'Do not promise an exact delivery date.' }
      reason { 'This is reusable delivery guidance.' }
    end

    trait :knowledge_ready do
      status { :ready }
      destination { 'knowledge' }
      target_section { nil }
      source_name { 'Returns policy' }
      suggested_instruction { 'Returns are accepted within 14 days.' }
      reason { 'This is a reusable business policy.' }
    end
  end
end
