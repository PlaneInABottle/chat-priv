FactoryBot.define do
  factory :ai_agent_release do
    ai_agent
    account { ai_agent.account }
    revision { 1 }
    source { 'publish' }
    snapshot { AiAgents::ReleaseSnapshot.for(ai_agent) }
    fingerprint { AiAgents::ReleaseSnapshot.fingerprint(snapshot) }
  end
end
