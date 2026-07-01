require 'rails_helper'

RSpec.describe AgentBots::AiResponseJob do
  include ActiveJob::TestHelper

  subject(:job) { described_class.perform_later(message) }

  let(:message) { create(:message) }
  let(:processor) { instance_double(AiAgents::LiveProcessor, perform: true) }

  before do
    clear_enqueued_jobs
  end

  it 'queues the job' do
    expect { job }.to have_enqueued_job(described_class).with(message).on_queue('high')
  end

  it 'executes the live processor' do
    allow(AiAgents::LiveProcessor).to receive(:new).with(message: message).and_return(processor)

    perform_enqueued_jobs { job }

    expect(processor).to have_received(:perform)
  end

  it 'does not execute the live processor for a stale buffered message' do
    allow(AiAgents::ResponseBuffer).to receive(:claim!).with(message, 'stale-token').and_return(false)
    allow(AiAgents::LiveProcessor).to receive(:new)

    described_class.perform_now(message, 'stale-token')

    expect(AiAgents::LiveProcessor).not_to have_received(:new)
  end

  it 'executes the live processor and completes the matching buffered message' do
    allow(AiAgents::ResponseBuffer).to receive(:claim!).with(message, 'current-token').and_return(true)
    allow(AiAgents::ResponseBuffer).to receive(:complete!)
    allow(AiAgents::LiveProcessor).to receive(:new).with(message: message).and_return(processor)

    described_class.perform_now(message, 'current-token')

    expect(processor).to have_received(:perform)
    expect(AiAgents::ResponseBuffer).to have_received(:complete!).with(message, 'current-token')
  end

  it 'only executes the live processor once for duplicate buffered delivery' do
    token = SecureRandom.uuid
    message.conversation.update!(additional_attributes: {
                                   'ai_response_buffer' => {
                                     'message_id' => message.id,
                                     'conversation_id' => message.conversation_id,
                                     'token' => token,
                                     'status' => 'scheduled'
                                   }
                                 })
    allow(AiAgents::LiveProcessor).to receive(:new).with(message: message).and_return(processor)

    described_class.perform_now(message, token)
    described_class.perform_now(message, token)

    expect(processor).to have_received(:perform).once
  end

  it 'does not execute for a stale token on the latest message' do
    current_token = SecureRandom.uuid
    message.conversation.update!(additional_attributes: {
                                   'ai_response_buffer' => {
                                     'message_id' => message.id,
                                     'conversation_id' => message.conversation_id,
                                     'token' => current_token,
                                     'status' => 'scheduled'
                                   }
                                 })
    allow(AiAgents::LiveProcessor).to receive(:new)

    described_class.perform_now(message, 'stale-token')

    expect(AiAgents::LiveProcessor).not_to have_received(:new)
  end

  it 'releases a claimed token for retry when processing raises' do
    token = SecureRandom.uuid
    message.conversation.update!(additional_attributes: {
                                   'ai_response_buffer' => {
                                     'message_id' => message.id,
                                     'conversation_id' => message.conversation_id,
                                     'token' => token,
                                     'status' => 'scheduled'
                                   }
                                 })
    failing_processor = instance_double(AiAgents::LiveProcessor, perform: true)
    allow(failing_processor).to receive(:perform).and_raise(StandardError, 'temporary failure')
    allow(AiAgents::LiveProcessor).to receive(:new).with(message: message).and_return(failing_processor, processor)

    expect { described_class.perform_now(message, token) }.to raise_error(StandardError, 'temporary failure')

    metadata = message.conversation.reload.additional_attributes['ai_response_buffer']
    expect(metadata['status']).to eq('scheduled')

    described_class.perform_now(message, token)

    expect(processor).to have_received(:perform)
    expect(message.conversation.reload.additional_attributes.dig('ai_response_buffer', 'status')).to eq('completed')
  end

  it 'does not release the token when completion raises after processing succeeds' do
    token = SecureRandom.uuid
    message.conversation.update!(additional_attributes: {
                                   'ai_response_buffer' => {
                                     'message_id' => message.id,
                                     'conversation_id' => message.conversation_id,
                                     'token' => token,
                                     'status' => 'scheduled'
                                   }
                                 })
    allow(AiAgents::LiveProcessor).to receive(:new).with(message: message).and_return(processor)
    allow(AiAgents::ResponseBuffer).to receive(:complete!).with(message, token).and_raise(StandardError, 'completion failure')

    expect { described_class.perform_now(message, token) }.to raise_error(StandardError, 'completion failure')

    metadata = message.conversation.reload.additional_attributes['ai_response_buffer']
    expect(metadata['status']).to eq('claimed')

    allow(AiAgents::ResponseBuffer).to receive(:complete!).and_call_original
    described_class.perform_now(message, token)

    expect(processor).to have_received(:perform).once
  end
end
