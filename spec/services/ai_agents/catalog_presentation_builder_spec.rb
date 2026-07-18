require 'rails_helper'

RSpec.describe AiAgents::CatalogPresentationBuilder do
  let(:account) { create(:account, locale: 'tr') }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:assistant_message) do
    {
      content: 'Uygun ürünümüz aşağıda.',
      terminal_action: 'present_catalog_products',
      tool_result: {
        presentation: {
          id: 'presentation-1',
          mode: 'products',
          items: [{
            item_id: 'variant:red',
            display_name: 'Red Screen',
            price: { amount: 499, currency: 'TRY' },
            image_scope: 'representative_product',
            images: []
          }]
        }
      }
    }
  end

  it 'uses the detected conversation language instead of the account locale' do
    conversation.update!(additional_attributes: { 'conversation_language' => 'en' })
    assistant_message[:content] = 'Our suitable product is below.'

    content = build_content

    expect(content).to include('Reference price: 499 TRY', 'Representative product image')
    expect(content).not_to include('Referans fiyat', 'Temsili ürün görseli')
  end

  it 'normalizes the widget browser language before falling back to the account locale' do
    account.update!(locale: 'en')
    conversation.update!(additional_attributes: { 'browser_language' => 'tr-TR' })

    content = build_content

    expect(content).to include('Referans fiyat: 499 TRY', 'Temsili ürün görseli')
    expect(content).not_to include('Reference price', 'Representative product image')
  end

  def build_content
    described_class.new(
      assistant_message: assistant_message,
      ai_agent: ai_agent,
      conversation: conversation,
      trigger_message_id: 123
    ).call.first.fetch(:content)
  end
end
