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
            maximum_dimensions: { width: 80, height: 150, unit: 'cm' },
            link: { url: 'https://store.example/red-screen' },
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

    expect(content).to include('Reference price: 499 TRY')
    expect(content).to include('Maximum dimensions: 80 × 150 cm')
    expect(content).to include('[Product link](https://store.example/red-screen)')
    expect(content).not_to include('Referans fiyat', 'Representative product image', 'Temsili ürün görseli')
  end

  it 'normalizes the widget browser language before falling back to the account locale' do
    account.update!(locale: 'en')
    conversation.update!(additional_attributes: { 'browser_language' => 'tr-TR' })

    content = build_content

    expect(content).to include('Referans fiyat: 499 TRY')
    expect(content).to include('Maksimum ölçü: 80 × 150 cm')
    expect(content).to include('[Ürün linki](https://store.example/red-screen)')
    expect(content).not_to include('Reference price', 'Representative product image', 'Temsili ürün görseli')
  end

  it 'uses a conversation language persisted after the builder was initialized' do
    account.update!(locale: 'en')
    builder = build_builder
    conversation.class.find(conversation.id).update!(
      additional_attributes: conversation.additional_attributes.merge('conversation_language' => 'tr')
    )

    content = builder.call.first.fetch(:content)

    expect(content).to include('Referans fiyat: 499 TRY')
    expect(content).to include('Maksimum ölçü: 80 × 150 cm')
    expect(content).to include('[Ürün linki](https://store.example/red-screen)')
    expect(content).not_to include('Reference price')
  end

  it 'does not describe a representative image when preparation fails' do
    assistant_message.dig(:tool_result, :presentation, :items).first[:images] = [
      'https://cdn.myikas.com/images/05d8a2b7-89af-41b3-b47f-b091868cfd8c/5a9ebce4-8b06-4b92-9ed2-a8ffadb435de/1080/sample.webp'
    ]
    media_preparer = instance_double(AiAgents::CatalogImagePreparer)
    allow(media_preparer).to receive(:prepare).and_raise(AiAgents::CatalogImagePreparer::InvalidImage, 'unavailable')

    spec = build_builder(media_preparer: media_preparer).call.first

    expect(spec.fetch(:content)).not_to include('Temsili ürün görseli')
    expect(spec.dig(:content_attributes, :ai_agent, :catalog_presentation, :image_attached)).to be(false)
    expect(spec.fetch(:message_params)).not_to have_key(:attachments)
  end

  def build_content
    build_builder.call.first.fetch(:content)
  end

  def build_builder(media_preparer: nil)
    described_class.new(
      assistant_message: assistant_message,
      ai_agent: ai_agent,
      conversation: conversation,
      trigger_message_id: 123,
      media_preparer: media_preparer
    )
  end
end
