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

    it 'canonicalizes structured instructions and forces the matching compiled prompt' do
      instructions = VoiceAgents::InstructionDocument.from_legacy('Structured body')
      source = {
        prompt: 'stale prompt',
        config: { sibling: true, instructions: instructions, authoring_profile: { tone: 'concise' } }
      }

      sanitized = described_class.sanitize(source)

      expect(sanitized['config']).to eq('sibling' => true, 'instructions' => instructions)
      expect(sanitized['prompt']).to eq(VoiceAgents::InstructionDocument.new(instructions).compile)
      expect(source[:prompt]).to eq('stale prompt')
    end

    it 'drops malformed stored instructions while preserving the legacy prompt' do
      sanitized = described_class.sanitize(prompt: 'Legacy', config: { instructions: { version: 3 }, sibling: true })

      expect(sanitized).to eq('prompt' => 'Legacy', 'config' => { 'sibling' => true })
    end

    it 'returns the safe allowed shape with an empty config for malformed input' do
      expect(described_class.sanitize(nil)).to eq('config' => {})
      expect(described_class.sanitize(config: 'invalid', prompt: 'Keep')).to eq('config' => {}, 'prompt' => 'Keep')
    end
  end

  describe '.for' do
    it 'builds a sanitized snapshot with canonical instructions' do
      instructions = VoiceAgents::InstructionDocument.from_legacy('Voice rules')
      agent = build(
        :voice_agent,
        prompt: 'stale',
        config: { 'runtime' => true, 'instructions' => instructions, 'authoring_profile' => { 'tone' => 'concise' } }
      )

      snapshot = described_class.for(agent)
      expect(snapshot.fetch('config')).to eq('runtime' => true, 'instructions' => instructions)
      expect(snapshot['prompt']).to eq(VoiceAgents::InstructionDocument.new(instructions).compile)
      reordered = snapshot.to_a.reverse.to_h
      reordered['config'] = snapshot['config'].to_a.reverse.to_h
      expect(AssistantReleases::Snapshot.fingerprint(snapshot)).to eq(
        AssistantReleases::Snapshot.fingerprint(reordered)
      )
    end
  end
end
