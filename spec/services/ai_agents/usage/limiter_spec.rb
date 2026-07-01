require 'rails_helper'

RSpec.describe AiAgents::Usage::Limiter do
  let(:account) do
    create(:account, settings: {
             ai_agent_enabled: true,
             ai_agent_conversation_limit: 2,
             ai_agent_conversation_reuse_window_hours: 24,
             reporting_timezone: 'America/New_York'
           })
  end
  let(:ai_agent) { create(:ai_agent, account: account, enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'pending') }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: contact) }
  let(:now) { Time.zone.parse('2026-06-05 15:00:00 UTC') }

  describe '#reserve!' do
    it 'reserves a monthly usage event for the current account period' do
      result = described_class.new(ai_agent: ai_agent, message: message, now: now).reserve!

      expect(result.status).to eq(:reserved)
      expect(result.event).to be_reserved
      expect(result.event.period_start_at).to eq(Time.zone.parse('2026-06-01 04:00:00 UTC'))
      expect(result.event.period_end_at).to eq(Time.zone.parse('2026-07-01 04:00:00 UTC'))
      expect(result.event.window_ends_at).to be_within(1.second).of(now + 24.hours)
    end

    it 'reuses an active same-contact window without reserving a new event' do
      existing_event = create(:ai_agent_usage_event,
                              account: account,
                              ai_agent: ai_agent,
                              contact: contact,
                              conversation: conversation,
                              period_start_at: Time.zone.parse('2026-06-01 04:00:00 UTC'),
                              period_end_at: Time.zone.parse('2026-07-01 04:00:00 UTC'),
                              window_started_at: 1.hour.ago,
                              window_ends_at: now + 2.hours,
                              status: :consumed)

      expect do
        result = described_class.new(ai_agent: ai_agent, message: message, now: now).reserve!
        expect(result.status).to eq(:reused)
        expect(result.event).to eq(existing_event)
      end.not_to change(AiAgentUsageEvent, :count)
    end

    it 'returns exhausted when active events reach the monthly limit' do
      create_list(:ai_agent_usage_event, 2,
                  account: account,
                  ai_agent: ai_agent,
                  period_start_at: Time.zone.parse('2026-06-01 04:00:00 UTC'),
                  period_end_at: Time.zone.parse('2026-07-01 04:00:00 UTC'),
                  window_started_at: now - 2.days,
                  window_ends_at: now - 1.day,
                  status: :consumed)

      result = described_class.new(ai_agent: ai_agent, message: message, now: now).reserve!

      expect(result.status).to eq(:exhausted)
      expect(result.summary[:remaining]).to eq(0)
    end

    it 'allows unlimited accounts without creating usage events' do
      account.update!(ai_agent_conversation_limit: 0)

      expect do
        result = described_class.new(ai_agent: ai_agent, message: message, now: now).reserve!
        expect(result.status).to eq(:unlimited)
      end.not_to change(AiAgentUsageEvent, :count)
    end
  end

  describe '#consume!' do
    it 'counts a successful reused response even if the original reservation was released' do
      first_limiter = described_class.new(ai_agent: ai_agent, message: message, now: now)
      first_result = first_limiter.reserve!
      second_message = create(:message,
                              account: account,
                              inbox: inbox,
                              conversation: conversation,
                              message_type: 'incoming',
                              sender: contact)
      second_limiter = described_class.new(ai_agent: ai_agent, message: second_message, now: now + 1.second)
      second_result = second_limiter.reserve!

      expect(second_result.status).to eq(:reused)
      expect(second_result.event).to eq(first_result.event)

      first_limiter.release!(first_result.event)
      second_limiter.consume!(second_result.event)

      expect(first_result.event.reload).to be_consumed
      expect(first_result.event.message_id).to eq(second_message.id)
      expect(AiAgentUsageEvent.consumed.count).to eq(1)
    end
  end

  describe '#exhausted_handoff!' do
    it 'opens the conversation with a private note and no public message' do
      result = described_class.new(ai_agent: ai_agent, message: message, now: now).reserve!
      limiter = described_class.new(ai_agent: ai_agent, message: message, now: now)

      expect do
        limiter.exhausted_handoff!(summary: result.summary)
      end.to change { conversation.messages.where(private: true).count }.by(1)
        .and change { conversation.messages.where(private: false, message_type: 'outgoing').count }.by(0)

      expect(conversation.reload).to be_open
      expect(conversation.additional_attributes['ai_usage_limit_exhausted']).to be(true)
      expect(conversation.additional_attributes['ai_handoff_completed']).to be(true)
    end
  end
end
