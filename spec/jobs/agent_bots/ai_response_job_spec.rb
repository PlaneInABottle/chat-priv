require 'rails_helper'

RSpec.describe AgentBots::AiResponseJob do
  include ActiveJob::TestHelper

  subject(:job) { described_class.perform_later(message) }

  let(:message) { create(:message) }

  it 'queues the job' do
    expect { job }.to have_enqueued_job(described_class).with(message).on_queue('high')
  end

  it 'executes the live processor' do
    processor = instance_double(AiAgents::LiveProcessor, perform: true)
    allow(AiAgents::LiveProcessor).to receive(:new).with(message: message).and_return(processor)

    perform_enqueued_jobs { job }

    expect(processor).to have_received(:perform)
  end
end
