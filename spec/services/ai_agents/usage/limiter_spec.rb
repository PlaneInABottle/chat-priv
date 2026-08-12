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

    it 'allows unlimited accounts without creating usage events when both limits are off' do
      account.update!(ai_agent_conversation_limit: 0, ai_agent_response_limit_per_window: 0)

      expect do
        result = described_class.new(ai_agent: ai_agent, message: message, now: now).reserve!
        expect(result.status).to eq(:unlimited)
      end.not_to change(AiAgentUsageEvent, :count)
    end

    it 'creates a window event for monthly-unlimited accounts when the response limit is active' do
      account.update!(ai_agent_conversation_limit: 0)

      expect do
        result = described_class.new(ai_agent: ai_agent, message: message, now: now).reserve!
        expect(result.status).to eq(:reserved)
        expect(result.event).to be_present
      end.to change(AiAgentUsageEvent, :count).by(1)
    end

    it 'never exhausts monthly for monthly-unlimited accounts with many past events' do
      account.update!(ai_agent_conversation_limit: 0)
      create_list(:ai_agent_usage_event, 5,
                  account: account,
                  ai_agent: ai_agent,
                  period_start_at: Time.zone.parse('2026-06-01 04:00:00 UTC'),
                  period_end_at: Time.zone.parse('2026-07-01 04:00:00 UTC'),
                  window_started_at: now - 2.days,
                  window_ends_at: now - 1.day,
                  status: :consumed)

      result = described_class.new(ai_agent: ai_agent, message: message, now: now).reserve!

      expect(result.status).to eq(:reserved)
      expect(result.summary[:unlimited]).to be(true)
    end

    it 'reuses the active window event for monthly-unlimited accounts with an active response limit' do
      account.update!(ai_agent_conversation_limit: 0)
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

  describe 'freemium monthly limits' do
    let(:freemium_account) do
      create(:account, settings: {
               ai_agent_enabled: true,
               ai_agent_conversation_limit: Account::FREEMIUM_AI_AGENT_CONVERSATION_MONTHLY_LIMIT,
               ai_agent_conversation_reuse_window_hours: 24,
               reporting_timezone: 'America/New_York'
             })
    end
    let(:freemium_ai_agent) { create(:ai_agent, account: freemium_account, enabled: true) }
    let(:freemium_inbox) { create(:inbox, account: freemium_account) }
    let(:june_start) { Time.zone.parse('2026-06-01 04:00:00 UTC') }
    let(:june_end) { Time.zone.parse('2026-07-01 04:00:00 UTC') }

    def build_incoming_message(account:, inbox:, content: 'Hello')
      contact = create(:contact, account: account)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact, status: 'pending')
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: contact, content: content)
    end

    def create_expired_consumed_event(account:, ai_agent:, period_start_at:, period_end_at:)
      create(:ai_agent_usage_event,
             account: account, ai_agent: ai_agent, period_start_at: period_start_at, period_end_at: period_end_at,
             window_started_at: Time.zone.parse('2026-06-01 05:00:00 UTC'),
             window_ends_at: Time.zone.parse('2026-06-02 05:00:00 UTC'),
             status: :consumed)
    end

    it 'reserves the 100th conversation and exhausts the 101st at the freemium limit' do
      create_list(:ai_agent_usage_event, 99,
                  account: freemium_account, ai_agent: freemium_ai_agent,
                  period_start_at: june_start, period_end_at: june_end,
                  window_started_at: Time.zone.parse('2026-06-01 05:00:00 UTC'),
                  window_ends_at: Time.zone.parse('2026-06-02 05:00:00 UTC'),
                  status: :consumed)

      first = described_class.new(ai_agent: freemium_ai_agent,
                                  message: build_incoming_message(account: freemium_account, inbox: freemium_inbox), now: now)

      expect { expect(first.reserve!.status).to eq(:reserved) }.to change(AiAgentUsageEvent, :count).by(1)
      expect(AiAgentUsageEvent.active.count).to eq(100)

      second = described_class.new(ai_agent: freemium_ai_agent,
                                   message: build_incoming_message(account: freemium_account, inbox: freemium_inbox), now: now)
      result = second.reserve!

      expect(result.status).to eq(:exhausted)
      expect(result.summary[:remaining]).to eq(0)
      expect(AiAgentUsageEvent.active.count).to eq(100)
    end

    it 'resets the quota at the reporting-timezone month boundary' do
      create_list(:ai_agent_usage_event, 100,
                  account: freemium_account, ai_agent: freemium_ai_agent,
                  period_start_at: june_start, period_end_at: june_end,
                  window_started_at: Time.zone.parse('2026-06-01 05:00:00 UTC'),
                  window_ends_at: Time.zone.parse('2026-06-02 05:00:00 UTC'),
                  status: :consumed)

      result = described_class.new(ai_agent: freemium_ai_agent,
                                   message: build_incoming_message(account: freemium_account, inbox: freemium_inbox),
                                   now: Time.zone.parse('2026-07-05 12:00:00 UTC')).reserve!

      expect(result.status).to eq(:reserved)
      expect(result.event.period_start_at).to eq(Time.zone.parse('2026-07-01 04:00:00 UTC'))
      expect(result.event.period_end_at).to eq(Time.zone.parse('2026-08-01 04:00:00 UTC'))
      expect(result.summary[:remaining]).to eq(99)
    end

    it 'applies limit changes immediately without rewriting usage events' do
      create_list(:ai_agent_usage_event, 50,
                  account: freemium_account, ai_agent: freemium_ai_agent,
                  period_start_at: june_start, period_end_at: june_end,
                  window_started_at: Time.zone.parse('2026-06-01 05:00:00 UTC'),
                  window_ends_at: Time.zone.parse('2026-06-02 05:00:00 UTC'),
                  status: :consumed)

      freemium_account.update!(ai_agent_conversation_limit: 10)
      lowered = described_class.new(ai_agent: freemium_ai_agent,
                                    message: build_incoming_message(account: freemium_account, inbox: freemium_inbox), now: now).reserve!

      expect(lowered.status).to eq(:exhausted)
      expect(lowered.summary[:remaining]).to eq(0)
      expect(AiAgentUsageEvent.active.count).to eq(50)

      freemium_account.update!(ai_agent_conversation_limit: 200)
      raised = described_class.new(ai_agent: freemium_ai_agent,
                                   message: build_incoming_message(account: freemium_account, inbox: freemium_inbox), now: now).reserve!

      expect(raised.status).to eq(:reserved)
      expect(raised.summary[:remaining]).to eq(149)
      expect(AiAgentUsageEvent.active.count).to eq(51)
    end

    it 'reserves a new event once the same contact reuse window expires' do
      contact = create(:contact, account: freemium_account)
      conversation = create(:conversation, account: freemium_account, inbox: freemium_inbox, contact: contact, status: 'pending')
      expired = create_expired_consumed_event(account: freemium_account, ai_agent: freemium_ai_agent,
                                              period_start_at: june_start, period_end_at: june_end)
      expired.update!(contact: contact, conversation: conversation)
      message = create(:message, account: freemium_account, inbox: freemium_inbox, conversation: conversation,
                                 message_type: 'incoming', sender: contact)

      result = described_class.new(ai_agent: freemium_ai_agent, message: message, now: now).reserve!

      expect(result.status).to eq(:reserved)
      expect(result.event).not_to eq(expired)
      expect(AiAgentUsageEvent.active.count).to eq(2)
    end
  end

  describe 'concurrent reservations' do
    self.use_transactional_tests = false

    it 'never over-allocates when reservations race for the same account' do
      account = create(:account, settings: {
                         ai_agent_enabled: true,
                         ai_agent_conversation_limit: 3,
                         ai_agent_conversation_reuse_window_hours: 24,
                         reporting_timezone: 'America/New_York'
                       })
      ai_agent = create(:ai_agent, account: account, enabled: true)
      agent_bot_id = ai_agent.agent_bot_id
      inbox = create(:inbox, account: account)
      web_widget_id = inbox.channel_id

      conversations = Array.new(6) do
        contact = create(:contact, account: account)
        create(:conversation, account: account, inbox: inbox, contact: contact, status: 'pending')
      end
      conversation_ids = conversations.map(&:id)
      contact_inbox_ids = Conversation.where(id: conversation_ids).pluck(:contact_inbox_id).compact
      messages = conversations.map do |conversation|
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming',
                         sender: conversation.contact)
      end

      results = Concurrent::Array.new
      barrier = Concurrent::CyclicBarrier.new(6)

      threads = messages.map do |message|
        Thread.new do
          barrier.wait
          results << described_class.new(ai_agent: ai_agent, message: message, now: now).reserve!.status
        end
      end

      unfinished = threads.reject { |thread| thread.join(30) }
      expect(unfinished).to be_empty
      threads.each(&:value)

      expect(results.count { |status| status == :reserved }).to eq(3)
      expect(results.count { |status| status == :exhausted }).to eq(3)
      expect(AiAgentUsageEvent.where(account: account).active.count).to eq(3)
      expect(AiAgentUsageEvent.where(account: account).reserved.count).to eq(3)
    ensure
      if account
        AiAgentUsageEvent.where(account_id: account.id).delete_all
        Conversation.where(account_id: account.id).delete_all
        ContactInbox.where(id: contact_inbox_ids).delete_all if contact_inbox_ids&.any?
        Message.where(account_id: account.id).delete_all
        Contact.where(account_id: account.id).delete_all
        Inbox.where(account_id: account.id).delete_all
        Channel::WebWidget.where(id: web_widget_id).delete_all if web_widget_id
        ai_agent&.delete
        AgentBot.where(id: agent_bot_id).delete_all if agent_bot_id
        account.delete
      end
    end
  end
end
