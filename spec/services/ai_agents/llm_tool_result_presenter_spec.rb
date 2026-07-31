require 'rails_helper'

RSpec.describe AiAgents::LlmToolResultPresenter do
  def candidate(index)
    {
      item_id: "item-#{index}",
      product_id: "product-#{index}",
      variant_id: "variant-#{index}",
      display_name: "Product #{index}",
      category_paths: ['Screens > Door screens'],
      price: { amount: index + 100, currency: 'TRY' },
      stock: { in_stock: true, sellable: true },
      evidence: [{ fact: 'color', value: 'Grey' }],
      relevance_score: 42,
      relevance_signals: [{ kind: 'fts_bm25_match', raw_score: 2.1, score: 4 }],
      image: { available: true, count: 2, scope: 'variant' },
      link: { url: "https://example.test/products/#{index}" }
    }
  end

  it 'keeps a compact catalog projection for one query without mutating the full result' do
    result = {
      status: 'ok',
      result_type: 'show_candidates',
      result_count: 20,
      parsed: { terms: %w[door screen] },
      search_backend: 'fts5',
      catalog: { snapshot_id: 9 },
      candidates: Array.new(20) { |index| candidate(index) }
    }

    presented = described_class.new(tool_key: 'ikas_catalog_search', result: result).call

    expect(presented.fetch('candidates').size).to eq(8)
    expect(presented.fetch('candidates').first).to include(
      'display_name' => 'Product 0',
      'item_id' => 'item-0',
      'price' => { 'amount' => 100, 'currency' => 'TRY' },
      'image' => { 'available' => true, 'count' => 2, 'scope' => 'variant' },
      'link' => { 'url' => 'https://example.test/products/0' }
    )
    expect(presented).to include('result_count' => 20, 'candidates_omitted' => 12)
    expect(presented).not_to include('parsed', 'search_backend', 'catalog')
    expect(presented.fetch('candidates').first).not_to include(
      'product_id', 'variant_id', 'confidence', 'match_kind', 'match_reasons', 'relevance_score', 'relevance_signals'
    )
    expect(presented.dig('candidates', 0, 'stock')).to eq('in_stock' => true, 'sellable' => true)
    expect(result.fetch(:candidates)).to have_attributes(size: 20).and start_with(include(:relevance_score, :relevance_signals))
  end

  it 'preserves query diversity while bounding multi-search candidates' do
    result = {
      status: 'ok',
      result_type: 'multi_search',
      result_count: 24,
      queries: Array.new(3) do |query_index|
        {
          query: "query #{query_index}",
          result_type: 'show_candidates',
          result_count: 8,
          candidates: Array.new(8) { |candidate_index| candidate((query_index * 10) + candidate_index) }
        }
      end
    }

    presented = described_class.new(tool_key: 'ikas_catalog_search', result: result).call

    expect(presented.fetch('queries').map { |query| query.fetch('candidates').size }).to eq([4, 4, 4])
    expect(presented.fetch('queries').map { |query| query.fetch('candidates_omitted') }).to eq([4, 4, 4])
    expect(presented.fetch('queries').map { |query| query.fetch('query') }).to eq(['query 0', 'query 1', 'query 2'])
  end

  it 'returns other tool results unchanged apart from stringifying keys' do
    result = { status: 'ok', orders: [{ tracking: { tracking_link: 'https://carrier.test/track/1' } }] }

    expect(described_class.new(tool_key: 'ikas_lookup_order', result: result).call).to eq(result.deep_stringify_keys)
  end
end
