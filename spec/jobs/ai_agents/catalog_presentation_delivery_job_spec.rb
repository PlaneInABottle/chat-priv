require 'rails_helper'

RSpec.describe AiAgents::CatalogPresentationDeliveryJob do
  let(:conversation) { create(:conversation) }

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
end
