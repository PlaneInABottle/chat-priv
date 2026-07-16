require 'rails_helper'

RSpec.describe AiAgents::Tools::PresentOptionsService do
  subject(:service) do
    described_class.new(ai_agent: nil, account: nil, mode: :test, settings: {}, tool_events: tool_events)
  end

  let(:tool_events) { [] }

  it 'builds a terminal input selection from general choices' do
    result = service.call(
      args: {
        'question' => 'Nasıl devam edelim?',
        'options' => [{ 'label' => 'Ürün seçimi' }, { 'label' => 'Sipariş desteği' }]
      }
    )

    expect(result).to include(status: 'ok', terminal_action: 'present_options', customer_message: 'Nasıl devam edelim?')
    expect(result.dig(:presentation, :content_type)).to eq('input_select')
    expect(result.dig(:presentation, :items).pluck(:title)).to eq(['Ürün seçimi', 'Sipariş desteği'])
    expect(result.dig(:presentation, :items).pluck(:value)).to all(match(/\A[0-9a-f-]{36}\z/))
  end

  it 'resolves catalog choices only from the latest successful catalog result' do
    tool_events << {
      'tool' => 'ikas_catalog_search',
      'status' => 'ok',
      'result' => {
        'result_type' => 'show_candidates',
        'candidates' => [
          { 'item_id' => 'variant:red', 'display_name' => 'Sineklik - Kırmızı', 'stock' => { 'sellable' => true } },
          { 'item_id' => 'variant:blue', 'display_name' => 'Sineklik - Mavi', 'stock' => { 'sellable' => true } },
          { 'item_id' => 'variant:gone', 'display_name' => 'Sineklik - Yok', 'stock' => { 'sellable' => false } }
        ]
      }
    }

    result = service.call(
      args: { 'question' => 'Hangi renk?', 'catalog_option_ids' => %w[variant:red variant:blue] }
    )

    expect(result.dig(:presentation, :items).pluck(:title)).to eq(['Sineklik - Kırmızı', 'Sineklik - Mavi'])
    expect(service.call(args: { 'question' => 'Hangi renk?', 'catalog_option_ids' => %w[variant:red variant:gone] })).to include(
      status: 'error', error_code: 'unknown_catalog_option', recoverable: true
    )
  end

  it 'resolves nested category buckets and multi-search candidates' do
    tool_events << {
      'tool' => 'ikas_catalog_search',
      'status' => 'ok',
      'result' => {
        'result_type' => 'multi_search',
        'queries' => [
          {
            'buckets' => [
              { 'category_id' => 'cat-door', 'label' => 'Kapı', 'children' => [{ 'category_id' => 'cat-slide', 'label' => 'Sürgülü' }] }
            ]
          },
          {
            'candidates' => [
              { 'item_id' => 'variant:white', 'display_name' => 'Beyaz Sineklik', 'stock' => { 'sellable' => true } }
            ]
          }
        ]
      }
    }

    result = service.call(args: { 'question' => 'Hangisi?', 'catalog_option_ids' => %w[cat-slide variant:white] })

    expect(result.dig(:presentation, :items).pluck(:title)).to eq(['Sürgülü', 'Beyaz Sineklik'])
  end

  it 'rejects malformed, duplicate, and ungrounded choices as recoverable' do
    expect(service.call(args: { 'question' => 'Choose', 'options' => [{ 'label' => 'Same' }, { 'label' => 'same' }] })).to include(
      status: 'error', error_code: 'invalid_options', recoverable: true
    )
    expect(service.call(args: { 'question' => 'Choose', 'options' => [{ 'label' => 'Valid' }, { 'label' => '' }, 'invalid'] })).to include(
      status: 'error', error_code: 'invalid_options', recoverable: true
    )
    expect(service.call(args: { 'question' => 'Choose', 'catalog_option_ids' => %w[a b] })).to include(
      status: 'error', error_code: 'catalog_evidence_required', recoverable: true
    )
    expect(service.call(args: { 'question' => 'Choose', 'options' => [{ 'label' => 'A' }], 'catalog_option_ids' => %w[a b] })).to include(
      status: 'error', error_code: 'invalid_option_source', recoverable: true
    )
  end
end
