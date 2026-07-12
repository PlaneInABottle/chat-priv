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
end
