# frozen_string_literal: true

FactoryBot.define do
  factory :ai_agent_test_conversation do
    account
    ai_agent
    title { 'New Test Conversation' }
    messages { [] }
  end
end
