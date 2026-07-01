FactoryBot.define do
  factory :ai_agent do
    account
    name { 'AI Asistan' }
    prompt { 'You are a helpful AI assistant.' }
    enabled { false }
    config { {} }

    trait :with_human_handoff_tool do
      config do
        {
          'tools' => {
            'enabled' => ['human_handoff'],
            'human_handoff' => {
              'allowed_labels' => ['vip', 'ai_handoff']
            }
          }
        }
      end
    end
  end
end
