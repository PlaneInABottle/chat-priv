FactoryBot.define do
  factory :ai_agent_llm_call do
    account
    ai_agent { association(:ai_agent, account: account) }
    step { 'initial' }
    mode { :test }
    status { :succeeded }
    request_messages { [{ 'role' => 'user', 'content' => 'Hello' }] }
    request_tool_names { [] }
    response { { 'assistant_text' => 'Hi' } }
    usage { {} }
  end
end
