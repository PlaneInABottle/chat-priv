require 'rails_helper'

RSpec.describe AiAgents::WebsiteImportApplier do
  let(:account) { create(:account) }
  let(:document) do
    AiAgents::InstructionDocument.new(
      'profile' => { 'language' => 'same_as_customer', 'tone' => 'friendly' },
      'sections' => {
        'identity' => 'Existing identity',
        'business_context' => 'Existing context',
        'rules' => 'Existing rules',
        'handoff' => 'Always hand off when asked.'
      }
    ).normalized
  end
  let(:ai_agent) do
    create(
      :ai_agent,
      account: account,
      config: { 'instructions' => document, 'tools' => { 'enabled' => ['human_handoff'] } },
      prompt: AiAgents::InstructionDocument.new(document).compile
    )
  end
  let(:website_import) do
    create(
      :ai_agent_website_import,
      :ready,
      account: account,
      ai_agent: ai_agent,
      base_draft_fingerprint: ai_agent.draft_fingerprint,
      proposed_sections: {
        'business_context' => 'Generated context',
        'rules' => 'Generated rules'
      }
    )
  end

  it 'applies only selected sections and preserves the remaining draft' do
    described_class.new(
      website_import: website_import,
      section_keys: ['business_context'],
      expected_draft_fingerprint: ai_agent.draft_fingerprint
    ).perform

    sections = ai_agent.reload.config.dig('instructions', 'sections')
    expect(sections).to include(
      'identity' => 'Existing identity',
      'business_context' => 'Generated context',
      'rules' => 'Existing rules',
      'handoff' => 'Always hand off when asked.'
    )
    expect(ai_agent.config.dig('tools', 'enabled')).to eq(['human_handoff'])
    expect(website_import.reload).to have_attributes(status: 'applied', proposed_sections: {})
  end

  it 'rejects an application after the assistant draft changes' do
    fingerprint = ai_agent.draft_fingerprint
    ai_agent.update!(prompt: "#{ai_agent.prompt}\nChanged")

    expect do
      described_class.new(
        website_import: website_import,
        section_keys: ['business_context'],
        expected_draft_fingerprint: fingerprint
      ).perform
    end.to raise_error(described_class::Conflict)
  end

  it 'does not accept a new client fingerprint for a stale proposal' do
    website_import
    ai_agent.update!(prompt: "#{ai_agent.prompt}\nChanged")

    expect do
      described_class.new(
        website_import: website_import,
        section_keys: ['business_context'],
        expected_draft_fingerprint: ai_agent.draft_fingerprint
      ).perform
    end.to raise_error(described_class::Conflict)
  end

  it 'rejects an application when the import mode changes' do
    website_import.update!(mode: :preview)

    expect do
      described_class.new(
        website_import: website_import,
        section_keys: ['business_context'],
        expected_draft_fingerprint: ai_agent.draft_fingerprint,
        required_mode: :initial
      ).perform
    end.to raise_error(described_class::Conflict)

    expect(website_import.reload).to have_attributes(status: 'ready', stage: 'complete')
  end
end
