FactoryBot.define do
  factory :ai_agent_usage_event do
    account
    ai_agent { association(:ai_agent, account: account) }
    contact { association(:contact, account: account) }
    conversation { association(:conversation, account: account, contact: contact) }
    message { association(:message, account: account, conversation: conversation, sender: contact) }
    period { :monthly }
    period_start_at { Time.current.beginning_of_month }
    period_end_at { Time.current.next_month.beginning_of_month }
    window_started_at { Time.current }
    window_ends_at { 24.hours.from_now }
    status { :consumed }
  end
end
