require 'rails_helper'

RSpec.describe AiAgents::CatalogPresentationDeliveryJob do
  let(:conversation) { create(:conversation) }
  let(:catalog_image_captions) { %w[First Second] }

  it 'delivers every presentation message once in sequence order' do
    messages = [2, 1, 3].map do |sequence|
      create(
        :message,
        conversation: conversation,
        account: conversation.account,
        inbox: conversation.inbox,
        message_type: 'outgoing',
        content_attributes: {
          'ai_agent' => {
            'catalog_presentation' => {
              'id' => 'presentation-1',
              'sequence' => sequence,
              'total' => 3
            }
          }
        }
      )
    end
    allow(SendReplyJob).to receive(:perform_now)

    described_class.perform_now(conversation.id, 'presentation-1')

    expect(SendReplyJob).to have_received(:perform_now).ordered.with(messages.second.id)
    expect(SendReplyJob).to have_received(:perform_now).ordered.with(messages.first.id)
    expect(SendReplyJob).to have_received(:perform_now).ordered.with(messages.third.id)
  end

  it 'fails for an incomplete group so the job can retry after persistence settles' do
    create(
      :message,
      conversation: conversation,
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: 'outgoing',
      content_attributes: {
        'ai_agent' => {
          'catalog_presentation' => {
            'id' => 'presentation-incomplete',
            'sequence' => 2,
            'total' => 3
          }
        }
      }
    )

    expect do
      described_class.perform_now(conversation.id, 'presentation-incomplete')
    end.to raise_error(RuntimeError, /is incomplete/)
  end

  %w[default whatsapp_cloud].each do |provider|
    it "delivers an ordered image group idempotently through #{provider}" do
      channel = create(:channel_whatsapp, provider: provider, sync_templates: false, validate_provider_config: false)
      contact_inbox = create(:contact_inbox, inbox: channel.inbox, source_id: '123456789')
      whatsapp_conversation = create(
        :conversation,
        account: channel.account,
        inbox: channel.inbox,
        contact: contact_inbox.contact,
        contact_inbox: contact_inbox
      )
      create(:message, conversation: whatsapp_conversation, account: channel.account, inbox: channel.inbox, message_type: :incoming)
      presentation_id = "presentation-#{provider}"
      messages = catalog_image_captions.each_with_index.map do |content, index|
        catalog_image_message(whatsapp_conversation, content, presentation_id, index + 1)
      end
      sent_bodies = []
      provider_request = stub_provider_requests(channel, sent_bodies)

      2.times { described_class.perform_now(whatsapp_conversation.id, presentation_id) }

      expect(provider_request).to have_been_requested.twice
      expect(sent_bodies.map { |body| body.dig('image', 'caption') }).to eq(%w[First Second])
      expect(sent_bodies).to all(include('to' => '123456789', 'type' => 'image'))
      expect(sent_bodies.map { |body| body.dig('image', 'link') }).to all(be_present)
      expect(messages.map { |message| message.reload.source_id }).to eq(%w[external-1 external-2])
    end
  end

  def catalog_image_message(conversation, content, presentation_id, sequence)
    message = create(
      :message,
      conversation: conversation,
      account: conversation.account,
      inbox: conversation.inbox,
      message_type: :outgoing,
      content: content,
      content_attributes: catalog_presentation_attributes(presentation_id, sequence)
    )
    attachment = message.attachments.create!(account: conversation.account, file_type: :image)
    Rails.root.join('spec/assets/avatar.png').open do |file|
      attachment.file.attach(io: file, filename: "product-#{sequence}.png", content_type: 'image/png')
    end
    message
  end

  def catalog_presentation_attributes(presentation_id, sequence)
    {
      'ai_agent' => {
        'catalog_presentation' => {
          'id' => presentation_id,
          'sequence' => sequence,
          'total' => 2
        }
      }
    }
  end

  def stub_provider_requests(channel, sent_bodies)
    endpoint = if channel.provider == 'whatsapp_cloud'
                 "https://graph.facebook.com/v13.0/#{channel.provider_config.fetch('phone_number_id')}/messages"
               else
                 'https://waba.360dialog.io/v1/messages'
               end

    stub_request(:post, endpoint).to_return do |request|
      sent_bodies << JSON.parse(request.body)
      {
        status: 200,
        body: { messages: [{ id: "external-#{sent_bodies.length}" }] }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      }
    end
  end
end
