FactoryBot.define do
  factory :ai_agent do
    account
    name { 'AI Asistan' }
    prompt { 'You are a helpful AI assistant.' }
    enabled { false }
    config { {} }
  end
end
