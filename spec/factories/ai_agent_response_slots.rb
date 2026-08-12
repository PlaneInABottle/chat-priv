FactoryBot.define do
  factory :ai_agent_response_slot do
    ai_agent_usage_event
    trigger_message do
      association(:message, account: ai_agent_usage_event.account, conversation: ai_agent_usage_event.conversation,
                            sender: ai_agent_usage_event.contact)
    end
    status { :reserved }
  end
end
