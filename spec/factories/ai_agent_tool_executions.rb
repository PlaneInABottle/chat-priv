FactoryBot.define do
  factory :ai_agent_tool_execution do
    account
    ai_agent { association(:ai_agent, account: account) }
    tool_key { 'human_handoff' }
    tool_name { 'human_handoff' }
    mode { :test }
    status { :executed }
    arguments { {} }
    result { { 'status' => 'ok' } }
  end
end
