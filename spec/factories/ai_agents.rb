FactoryBot.define do
  factory :ai_agent do
    account
    prompt { 'You are a helpful AI assistant.' }
    enabled { false }
    config { {} }
  end
end
