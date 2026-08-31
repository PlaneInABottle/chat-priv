require 'rails_helper'

RSpec.describe VoiceAgents::InstructionDocument do
  let(:parity_cases) { JSON.parse(Rails.root.join('spec/fixtures/voice_instruction_documents.json').read) }
  let(:document) { parity_cases.find { |test_case| test_case['locale'] == 'en' }.fetch('document') }

  it 'returns only canonical Voice keys in deterministic order' do
    normalized = described_class.new(document).normalized
    expect(normalized.keys).to eq(%w[version locale profile sections])
    expect(normalized['profile'].keys).to eq(%w[language tone formality response_length])
    expect(normalized['sections'].keys).to eq(%w[business_context tasks rules])
  end

  it 'rejects unknown, malformed, and unsupported values' do
    expect { described_class.new(document.merge('identity' => 'x')).normalized }.to raise_error(ArgumentError)
    expect { described_class.new(document.merge('version' => 3)).normalized }.to raise_error(ArgumentError)
    expect { described_class.new(document.merge('locale' => 'de')).normalized }.to raise_error(ArgumentError)
    invalid_sections = document.merge('sections' => document['sections'].merge('handoff' => 'x'))
    expect { described_class.new(invalid_sections).normalized }.to raise_error(ArgumentError)
    expect { described_class.new(document.merge('profile' => document['profile'].merge('tone' => 'warm'))).normalized }.to raise_error(ArgumentError)
  end

  it 'projects the exact legacy prompt into rules only' do
    normalized = described_class.from_legacy("Exact <body>\nLine 2")
    expect(normalized['sections']).to eq('business_context' => '', 'tasks' => '', 'rules' => "Exact <body>\nLine 2")
  end

  it 'compiles through shared profile and localization primitives without text-only sections' do
    compiled = described_class.new(document).compile
    expect(compiled).to eq(parity_cases.find { |test_case| test_case['locale'] == 'en' }.fetch('compiled'))
    expect(compiled).not_to include('Identity and purpose', 'Human handoff', 'Example conversations', 'Additional instructions')
    expect(described_class.new(document).content_length).to eq(compiled.length)
  end

  it 'matches the canonical Turkish compiler output' do
    test_case = parity_cases.find { |item| item['locale'] == 'tr' }
    expect(described_class.new(test_case.fetch('document')).compile).to eq(test_case.fetch('compiled'))
  end
end
