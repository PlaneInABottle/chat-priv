require 'rails_helper'

RSpec.describe AiAgents::CatalogPresentationHistory do
  let(:channel) { create(:channel_whatsapp, sync_templates: false, validate_provider_config: false) }
  let(:contact_inbox) { create(:contact_inbox, inbox: channel.inbox, source_id: '123456789') }
  let(:conversation) do
    create(
      :conversation,
      account: channel.account,
      inbox: channel.inbox,
      contact: contact_inbox.contact,
      contact_inbox: contact_inbox
    )
  end
  let(:image_key) { Digest::SHA256.hexdigest('https://cdn.myikas.com/product.webp') }

  it 'does not treat a failed WhatsApp image as presented' do
    create_catalog_message(status: :failed)

    history = described_class.new(conversation)

    expect(history.presented_item_ids).to be_empty
    expect(history.presented_image_keys('variant:red')).to be_empty
  end

  it 'includes a successfully delivered WhatsApp image' do
    create_catalog_message(status: :sent, source_id: 'external-message-1', delivery_status: 'delivered')

    history = described_class.new(conversation)

    expect(history.presented_item_ids).to eq(['variant:red'])
    expect(history.presented_image_keys('variant:red')).to contain_exactly(image_key)
  end

  def create_catalog_message(status:, source_id: nil, delivery_status: nil)
    presentation = {
      'id' => 'presentation-1',
      'sequence' => 1,
      'total' => 1,
      'item_id' => 'variant:red',
      'image_attached' => true,
      'image_key' => image_key
    }
    presentation['delivery_status'] = delivery_status if delivery_status

    create(
      :message,
      account: channel.account,
      inbox: channel.inbox,
      conversation: conversation,
      message_type: :outgoing,
      status: status,
      source_id: source_id,
      content_attributes: { 'ai_agent' => { 'catalog_presentation' => presentation } }
    )
  end
end
