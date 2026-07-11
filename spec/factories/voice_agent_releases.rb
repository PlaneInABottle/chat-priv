FactoryBot.define do
  factory :voice_agent_release do
    voice_agent
    account { voice_agent.account }
    revision { 1 }
    source { 'publish' }
    snapshot { VoiceAgents::ReleaseSnapshot.for(voice_agent) }
    fingerprint { AssistantReleases::Snapshot.fingerprint(snapshot) }
  end
end
