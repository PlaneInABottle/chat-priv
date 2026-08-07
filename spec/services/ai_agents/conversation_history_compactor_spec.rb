require 'rails_helper'

RSpec.describe AiAgents::ConversationHistoryCompactor do
  it 'compacts a live image-message group into one assistant history entry' do
    messages = [
      { role: 'user', content: 'Balkon ürünlerini göster' },
      live_product_message('group-1', '1', 'Akordeon Sineklik\n\n499 TRY'),
      live_product_message('group-1', '2', 'Menteşeli Sineklik\n\n599 TRY'),
      { role: 'user', content: 'Başka ürünlerimizi de göster' }
    ]

    result = described_class.new(messages).call

    expect(result.length).to eq(3)
    expect(result.second[:content]).to include('Akordeon Sineklik', 'Menteşeli Sineklik')
    expect(result.second).not_to include(:catalog_item_ids)
  end

  it 'adds displayed product names to a test-conversation presentation' do
    result = described_class.new([
                                   {
                                     role: 'assistant',
                                     content: 'Ürünlerimiz aşağıda.',
                                     terminal_action: 'present_catalog_products',
                                     tool_result: {
                                       presentation: {
                                         id: 'group-2',
                                         items: [{ display_name: 'Kedi Tüllü Sineklik' }, { display_name: 'Pileli Sineklik' }]
                                       }
                                     }
                                   }
                                 ]).call

    expect(result.one?).to be(true)
    expect(result.first[:content]).to include('Ürünlerimiz aşağıda.', '1. Kedi Tüllü Sineklik', '2. Pileli Sineklik')
  end

  it 'adds displayed option titles to a present_options presentation without leaking values' do
    result = described_class.new([
                                   {
                                     role: 'assistant',
                                     content: 'Hangi akordiyon sineklik türü hakkında bilgi almak istersiniz?',
                                     terminal_action: 'present_options',
                                     tool_result: {
                                       presentation: {
                                         items: [
                                           { title: 'Double Akordiyon Kapı', value: 'opaque-value-1' },
                                           { title: 'Double Akordiyon Pencere', value: 'opaque-value-2' }
                                         ]
                                       }
                                     }
                                   }
                                 ]).call

    expect(result.one?).to be(true)
    content = result.first[:content]
    expect(content).to include(
      'Hangi akordiyon sineklik türü hakkında bilgi almak istersiniz?',
      '1. Double Akordiyon Kapı',
      '2. Double Akordiyon Pencere'
    )
    expect(content).not_to include('opaque-value-1', 'opaque-value-2')
  end

  def live_product_message(id, sequence, content)
    {
      role: 'assistant',
      content: content,
      catalog_presentation: { id: id, sequence: sequence }
    }
  end
end
