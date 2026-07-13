require 'rails_helper'

RSpec.describe AiAgents::AutomaticLearningCapture do
  include ActiveJob::TestHelper

  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:ai_agent) { create(:ai_agent, account: account, auto_learning_enabled: true) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let!(:handoff_message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Can I return my order?')
  end

  before do
    conversation.update!(
      additional_attributes: {
        'ai_handoff_completed' => true,
        'ai_handoff_by_ai_agent_id' => ai_agent.id,
        'ai_handoff_message_id' => handoff_message.id
      }
    )
    clear_enqueued_jobs
  end

  it 'captures the latest public human reply when a handed-off conversation is resolved' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent,
                     content: 'Let me check.')
    final_reply = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      sender: agent,
      content: 'Returns are accepted within 14 days.'
    )
    conversation.update!(status: :resolved)
    clear_enqueued_jobs

    expect { described_class.new(conversation: conversation).perform }
      .to change(AiAgentLearningSuggestion, :count).by(1)
      .and have_enqueued_job(AiAgents::LearningSuggestionJob)

    expect(ai_agent.learning_suggestions.last).to have_attributes(
      source_message: final_reply,
      submitted_by: agent,
      human_answer: 'Returns are accepted within 14 days.'
    )
  end

  it 'does not capture when the assistant setting is disabled' do
    ai_agent.update!(auto_learning_enabled: false)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent,
                     content: 'A reusable answer.')
    conversation.update!(status: :resolved)

    expect { described_class.new(conversation: conversation).perform }.not_to change(AiAgentLearningSuggestion, :count)
  end

  it 'does not capture ordinary human conversations without an AI handoff' do
    conversation.update!(additional_attributes: {})
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent,
                     content: 'A reusable answer.')
    conversation.update!(status: :resolved)

    expect { described_class.new(conversation: conversation).perform }.not_to change(AiAgentLearningSuggestion, :count)
  end

  it 'creates at most one review observation per conversation' do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, sender: agent,
                     content: 'A reusable answer.')
    conversation.update!(status: :resolved)
    capture = described_class.new(conversation: conversation)

    capture.perform

    expect { capture.perform }.not_to change(AiAgentLearningSuggestion, :count)
  end
end
