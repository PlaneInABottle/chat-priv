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
      },
      proposed_knowledge_content: "# Example\nSource: https://example.com/\nVerified company details.",
      source_urls: ['https://example.com/']
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
    expect(website_import.reload).to have_attributes(
      status: 'applied',
      base_document: nil,
      proposed_sections: {},
      proposed_knowledge_content: nil
    )
  end

  it 'preserves a legacy prompt when structured instructions do not exist' do
    legacy_prompt = 'Keep this existing customer guidance.'
    ai_agent.update!(config: { 'tools' => { 'enabled' => ['human_handoff'] } }, prompt: legacy_prompt)
    website_import.update!(base_draft_fingerprint: ai_agent.draft_fingerprint)

    described_class.new(
      website_import: website_import,
      section_keys: ['business_context'],
      expected_draft_fingerprint: ai_agent.draft_fingerprint
    ).perform

    expect(ai_agent.reload.prompt).to include(legacy_prompt, 'Generated context')
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

  it 'saves local instruction edits and selected suggestions atomically' do
    local_document = document.deep_dup
    local_document['sections']['identity'] = 'Customer-edited identity'

    described_class.new(
      website_import: website_import,
      section_keys: ['rules'],
      current_document: local_document,
      expected_draft_fingerprint: ai_agent.draft_fingerprint
    ).perform

    expect(ai_agent.reload.config.dig('instructions', 'sections')).to include(
      'identity' => 'Customer-edited identity',
      'business_context' => 'Existing context',
      'rules' => 'Generated rules'
    )
  end

  it 'creates and assigns website knowledge only when explicitly selected' do
    expect do
      described_class.new(
        website_import: website_import,
        section_keys: [],
        attach_knowledge: true,
        expected_draft_fingerprint: ai_agent.draft_fingerprint
      ).perform
    end.to change(AiKnowledgeSource, :count).by(1)

    source = account.ai_knowledge_sources.last
    expect(source).to have_attributes(
      source_type: 'website',
      website_url: 'https://example.com/',
      sync_status: 'ready'
    )
    expect(source.content).to include('Verified company details')
    expect(ai_agent.reload.knowledge_source_ids).to contain_exactly(source.id)
    expect(website_import.reload.ai_knowledge_source_id).to eq(source.id)
  end

  it 'requires a fresh analysis for rows without a comparison baseline' do
    website_import.update!(base_document: nil)

    expect do
      described_class.new(
        website_import: website_import,
        section_keys: ['rules'],
        expected_draft_fingerprint: ai_agent.draft_fingerprint
      ).perform
    end.to raise_error(described_class::InvalidSelection, /run again/)
  end
end
