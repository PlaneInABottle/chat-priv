require 'rails_helper'

RSpec.describe AiAgentLearningListener do
  let(:listener) { described_class.instance }
  let(:conversation) { create(:conversation) }
  let(:event) { Events::Base.new('conversation.resolved', Time.zone.now, conversation: conversation) }
  let(:capture) { instance_double(AiAgents::AutomaticLearningCapture, perform: nil) }

  it 'checks resolved conversations for an automatic learning observation' do
    allow(AiAgents::AutomaticLearningCapture).to receive(:new).with(conversation: conversation).and_return(capture)

    listener.conversation_resolved(event)

    expect(capture).to have_received(:perform)
  end

  it 'does not break event delivery when capture fails' do
    allow(AiAgents::AutomaticLearningCapture).to receive(:new).and_raise(StandardError, 'capture failed')
    allow(Rails.logger).to receive(:error)

    expect { listener.conversation_resolved(event) }.not_to raise_error
    expect(Rails.logger).to have_received(:error).with(/capture failed/)
  end
end
