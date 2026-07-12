require 'rails_helper'

RSpec.describe AiAgents::Tools::KnowledgeSearchService do
  it 'returns matching excerpts and source attribution from the runtime snapshot' do
    service = described_class.new(
      knowledge_sources: [
        { id: 12, name: 'Returns', content: 'Custom-sized products are reviewed for return within 14 days.' }
      ]
    )

    result = service.call(args: { 'query' => 'custom product return within 14 days' })

    expect(result).to include(status: 'ok', result_type: 'matches', result_count: 1)
    expect(result[:matches].first).to include(source_id: 12, source_name: 'Returns')
    expect(result[:attributions]).to eq([{ source_id: 12, source_name: 'Returns' }])
  end
end
