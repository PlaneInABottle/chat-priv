require 'rails_helper'

RSpec.describe VoiceAgents::ReleaseSnapshot do
  describe '.sanitize' do
    it 'deep-stringifies allowed runtime keys and removes reserved metadata without mutating the source' do
      source = {
        prompt: 'Runtime prompt',
        config: { sibling: true, authoring_profile: { tone: 'concise' } },
        knowledge_sources: [{ id: 1 }],
        unexpected: 'drop'
      }
      original = source.deep_dup

      expect(described_class.sanitize(source)).to eq(
        'prompt' => 'Runtime prompt',
        'config' => { 'sibling' => true },
        'knowledge_sources' => [{ 'id' => 1 }]
      )
      expect(source).to eq(original)
    end

    it 'returns the safe allowed shape with an empty config for malformed input' do
      expect(described_class.sanitize(nil)).to eq('config' => {})
      expect(described_class.sanitize(config: 'invalid', prompt: 'Keep')).to eq('config' => {}, 'prompt' => 'Keep')
    end
  end

  describe '.for' do
    it 'builds a runtime-only snapshot' do
      agent = build(:voice_agent, config: { 'runtime' => true, 'authoring_profile' => { 'tone' => 'concise' } })

      expect(described_class.for(agent).fetch('config')).to eq('runtime' => true)
    end
  end
end
