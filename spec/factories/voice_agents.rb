FactoryBot.define do
  factory :voice_agent do
    account
    name { 'Voice Assistant' }
    enabled { true }
    greeting { 'Merhaba, size nasil yardimci olabilirim?' }
    prompt { 'Kisa ve dogal cevap ver.' }
    architecture { 'realtime' }
    provider { 'gemini' }
    voice { 'Charon' }
    language { 'tr' }
    tools_config { VoiceAgents::Config.new({}).normalized_config }
    config { {} }
  end
end
