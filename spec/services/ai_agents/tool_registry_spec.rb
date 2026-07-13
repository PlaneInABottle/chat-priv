require 'rails_helper'

RSpec.describe AiAgents::ToolRegistry do
  it 'provides knowledge search at runtime without exposing it as a configurable tool' do
    expect(described_class.keys).not_to include(AiAgents::Config::KNOWLEDGE_SEARCH_TOOL)
    expect(described_class.find(AiAgents::Config::KNOWLEDGE_SEARCH_TOOL)).to have_attributes(
      name: 'search_knowledge',
      service_class: 'AiAgents::Tools::KnowledgeSearchService',
      terminal: false
    )
  end

  it 'requires handoff messages and teammate context to use the customer language' do
    properties = described_class::HUMAN_HANDOFF_INPUT_SCHEMA[:properties]

    expect(properties.dig(:customer_message, :description)).to include('same language as the latest customer message')
    expect(properties.dig(:internal_note, :description)).to include('customer conversation language')
  end
end
