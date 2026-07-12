require 'rails_helper'

RSpec.describe AiKnowledgeSources::Retriever do
  let(:sources) do
    [
      {
        id: 2,
        name: 'Returns and exchanges',
        content: 'Customers can request a return or exchange within 14 days. Custom products require human review.'
      },
      {
        id: 1,
        name: 'Delivery policy',
        content: 'Standard delivery takes three to five business days. Tracking is sent after dispatch.'
      }
    ]
  end

  it 'ranks matching verified sources and returns attribution' do
    result = described_class.new(sources: sources).call(query: 'custom product return policy')

    expect(result).to include(status: 'ok', result_type: 'matches', result_count: 1)
    expect(result[:matches].first).to include(source_id: 2, source_name: 'Returns and exchanges')
    expect(result[:matches].first[:excerpt]).to include('Custom products require human review')
    expect(result[:attributions]).to eq([{ source_id: 2, source_name: 'Returns and exchanges' }])
  end

  it 'returns a safe no-match payload without guessing' do
    result = described_class.new(sources: sources).call(query: 'warranty coverage')

    expect(result).to include(status: 'ok', result_type: 'no_match', result_count: 0, matches: [], attributions: [])
  end

  it 'rejects queries without searchable terms' do
    result = described_class.new(sources: sources).call(query: 'the and with')

    expect(result).to include(status: 'error', error_code: 'invalid_query')
  end
end
