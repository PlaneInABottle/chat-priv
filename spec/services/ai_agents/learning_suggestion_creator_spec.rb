require 'rails_helper'

RSpec.describe AiAgents::LearningSuggestionCreator do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:user) { create(:user, account: account) }

  before do
    AgentBotInbox.create!(account: account, agent_bot: ai_agent.agent_bot, inbox: inbox)
  end

  it 'snapshots the preceding customer question and queues analysis' do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'When will my order arrive?'
    )
    human_reply = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      sender: user,
      content: 'Delivery time depends on the destination.'
    )

    suggestion = nil
    expect do
      suggestion = described_class.new(message: human_reply, submitted_by: user).perform
    end.to have_enqueued_job(AiAgents::LearningSuggestionJob)

    expect(suggestion).to have_attributes(
      ai_agent: ai_agent,
      customer_message: 'When will my order arrive?',
      human_answer: 'Delivery time depends on the destination.',
      status: 'pending'
    )
  end

  it 'returns the existing suggestion without queuing duplicate analysis' do
    customer_message = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Can I return this?'
    )
    human_reply = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      sender: user,
      content: 'Returns are accepted within 14 days.'
    )
    existing = create(
      :ai_agent_learning_suggestion,
      account: account,
      ai_agent: ai_agent,
      conversation: conversation,
      source_message: human_reply,
      customer_message: customer_message.content
    )

    expect do
      result = described_class.new(message: human_reply, submitted_by: user).perform
      expect(result).to eq(existing)
    end.not_to have_enqueued_job(AiAgents::LearningSuggestionJob)
  end

  it 'rejects private notes' do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Can I return this?'
    )
    private_note = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      sender: user,
      private: true,
      content: 'Internal return note'
    )

    expect do
      described_class.new(message: private_note, submitted_by: user).perform
    end.to raise_error(described_class::InvalidCandidate, /public human replies/)
  end

  it 'rejects replies from an AI agent bot' do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Can I return this?'
    )
    bot_reply = create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      sender: ai_agent.agent_bot,
      content: 'Returns are accepted within 14 days.'
    )

    expect do
      described_class.new(message: bot_reply, submitted_by: user).perform
    end.to raise_error(described_class::InvalidCandidate, /public human replies/)
  end
end
