require 'rails_helper'

RSpec.describe AiAgents::LearningSuggestionApplier do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:reviewer) { create(:user, account: account) }
  let(:instruction_document) do
    {
      'version' => 3,
      'profile' => AiAgents::InstructionDocument::DEFAULT_PROFILE,
      'sections' => {
        'business_context' => 'We sell window screens.',
        'rules' => 'Never invent a price.'
      }
    }
  end
  let(:ai_agent) do
    create(
      :ai_agent,
      account: account,
      enabled: true,
      prompt: AiAgents::InstructionDocument.new(instruction_document).compile,
      config: {
        'instructions' => instruction_document,
        'tools' => { 'enabled' => ['human_handoff'] }
      },
      published_prompt: 'LIVE INSTRUCTIONS',
      published_config: { 'tools' => { 'enabled' => ['human_handoff'] } },
      published_revision: 1,
      published_at: Time.current
    )
  end
  let(:suggestion) do
    create(
      :ai_agent_learning_suggestion,
      :ready,
      account: account,
      ai_agent: ai_agent
    )
  end

  it 'appends reviewed guidance to the structured draft without changing the live release' do
    described_class.new(
      suggestion: suggestion,
      reviewer: reviewer,
      instruction: 'Do not promise an exact delivery date.',
      target_section: 'rules'
    ).perform

    ai_agent.reload
    expect(ai_agent.config.dig('instructions', 'sections', 'rules')).to eq(
      "Never invent a price.\n\nDo not promise an exact delivery date."
    )
    expect(ai_agent.config.dig('tools', 'enabled')).to eq(['human_handoff'])
    expect(ai_agent.prompt).to include('Do not promise an exact delivery date.')
    expect(ai_agent.live_prompt).to eq('LIVE INSTRUCTIONS')
    expect(ai_agent).to have_attributes(enabled: true, published_revision: 1)
    expect(ai_agent).to be_draft_changes
    expect(suggestion.reload).to have_attributes(
      status: 'applied',
      reviewed_by: reviewer,
      target_section: 'rules'
    )
  end

  it 'rejects a suggestion that is no longer ready' do
    suggestion.update!(status: :dismissed)

    expect do
      described_class.new(
        suggestion: suggestion,
        reviewer: reviewer,
        instruction: 'Do not promise an exact delivery date.',
        target_section: 'rules'
      ).perform
    end.to raise_error(described_class::InvalidSuggestion, /Only ready/)
  end
end
