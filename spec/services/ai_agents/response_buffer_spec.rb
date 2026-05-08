require 'rails_helper'

RSpec.describe AiAgents::ResponseBuffer do
  include ActiveJob::TestHelper

  let(:conversation) { create(:conversation, additional_attributes: { 'existing_key' => 'existing_value' }) }
  let(:message) do
    create(:message, account: conversation.account, inbox: conversation.inbox, conversation: conversation, message_type: 'incoming',
                     sender: conversation.contact)
  end

  before do
    clear_enqueued_jobs
  end

  it 'stores scheduled metadata and preserves existing additional attributes' do
    described_class.schedule!(message)

    metadata = conversation.reload.additional_attributes['ai_response_buffer']
    expect(conversation.additional_attributes['existing_key']).to eq('existing_value')
    expect(metadata['message_id']).to eq(message.id)
    expect(metadata['conversation_id']).to eq(conversation.id)
    expect(metadata['token']).to be_present
    expect(metadata['status']).to eq('scheduled')
  end

  it 'only claims a matching latest message and token once' do
    described_class.schedule!(message)
    token = conversation.reload.additional_attributes.dig('ai_response_buffer', 'token')

    expect(described_class.claim!(message, token)).to be(true)
    expect(described_class.claim!(message, token)).to be(false)
  end

  it 'rejects a stale token for the same latest message' do
    described_class.schedule!(message)

    expect(described_class.claim!(message, 'stale-token')).to be(false)
  end

  it 'falls back to immediate enqueue when config is zero' do
    allow(GlobalConfig).to receive(:get_value).with('AI_AGENT_RESPONSE_BUFFER_SECONDS').and_return('0')

    expect { described_class.schedule!(message) }
      .to have_enqueued_job(AgentBots::AiResponseJob).with(message).on_queue('high')
  end
end
