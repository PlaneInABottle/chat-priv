require 'rails_helper'

RSpec.describe AiAgents::Usage::Summary do
  let(:account) do
    create(:account, settings: {
             ai_agent_enabled: true,
             ai_agent_conversation_limit: 5,
             ai_agent_conversation_reuse_window_hours: 48,
             reporting_timezone: 'Etc/UTC'
           })
  end
  let(:ai_agent) { create(:ai_agent, account: account) }
  let(:now) { Time.zone.parse('2026-06-05 12:00:00 UTC') }

  it 'returns current monthly limit, remaining usage, reset time, and operational metrics' do
    conversation = create(:conversation, account: account)
    message = create(:message, account: account, conversation: conversation, message_type: 'incoming')
    create(:ai_agent_usage_event,
           account: account,
           ai_agent: ai_agent,
           conversation: conversation,
           message: message,
           period_start_at: Time.zone.parse('2026-06-01 00:00:00 UTC'),
           period_end_at: Time.zone.parse('2026-07-01 00:00:00 UTC'),
           status: :consumed)
    create(:ai_agent_llm_call,
           account: account,
           ai_agent: ai_agent,
           conversation: conversation,
           message: message,
           mode: :live,
           status: :succeeded,
           created_at: now)
    create(:ai_agent_tool_execution,
           account: account,
           ai_agent: ai_agent,
           conversation: conversation,
           message: message,
           mode: :live,
           status: :executed,
           created_at: now)

    payload = described_class.new(account: account, now: now, include_recent_events: true).payload

    expect(payload).to include(
      period: 'monthly',
      limit: 5,
      used: 1,
      remaining: 4,
      unlimited: false,
      status: 'ok',
      reuse_window_hours: 48
    )
    expect(payload[:reset_at]).to eq('2026-07-01T00:00:00Z')
    expect(payload[:metrics]).to include(counted_conversations: 1, ai_replies: 1, tool_calls: 1)
    expect(payload[:recent_events].first[:conversation_id]).to eq(conversation.id)
  end
end
