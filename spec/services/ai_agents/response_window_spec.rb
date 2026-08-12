# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgents::ResponseWindow do
  let(:account) do
    create(:account, settings: {
             ai_agent_enabled: true,
             ai_agent_conversation_limit: 0,
             ai_agent_response_limit_per_window: 50,
             ai_agent_conversation_reuse_window_hours: 24,
             reporting_timezone: 'America/New_York'
           })
  end
  let(:ai_agent) { create(:ai_agent, account: account, enabled: true) }
  let(:contact) { create(:contact, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, status: 'pending') }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: contact) }
  let(:event) do
    create(:ai_agent_usage_event, account: account, ai_agent: ai_agent, contact: contact, conversation: conversation, status: :reserved)
  end
  let(:window) { described_class.new(ai_agent: ai_agent, message: message) }

  def create_consumed_slots(count, usage_event: event, in_conversation: conversation)
    count.times do
      trigger = create(:message, account: account, inbox: inbox, conversation: in_conversation, message_type: 'incoming', sender: contact)
      create(:ai_agent_response_slot, ai_agent_usage_event: usage_event, trigger_message: trigger, status: :consumed)
    end
  end

  describe 'limit and warning threshold' do
    it 'reads the effective per-account override' do
      expect(window.limit).to eq(50)

      account.update!(ai_agent_response_limit_per_window: 0)
      expect(described_class.new(ai_agent: ai_agent, message: message).limit).to eq(0)
    end

    it 'derives the warning threshold as limit - 5 only when limit is above 5' do
      expect(window.warning_threshold).to eq(45)

      account.update!(ai_agent_response_limit_per_window: 6)
      expect(described_class.new(ai_agent: ai_agent, message: message).warning_threshold).to eq(1)

      account.update!(ai_agent_response_limit_per_window: 5)
      expect(described_class.new(ai_agent: ai_agent, message: message).warning_threshold).to eq(0)

      account.update!(ai_agent_response_limit_per_window: 3)
      expect(described_class.new(ai_agent: ai_agent, message: message).warning_threshold).to eq(0)
    end
  end

  describe '#reserve!' do
    it 'returns inactive when there is no usage event' do
      result = window.reserve!(event: nil)

      expect(result.status).to eq(:inactive)
      expect(result.slot).to be_nil
    end

    it 'returns inactive when the effective limit is zero' do
      account.update!(ai_agent_response_limit_per_window: 0)

      result = described_class.new(ai_agent: ai_agent, message: message).reserve!(event: event)

      expect(result.status).to eq(:inactive)
    end

    it 'reserves a new slot for a fresh trigger' do
      result = window.reserve!(event: event, trigger_message_id: message.id)

      expect(result.status).to eq(:reserved)
      expect(result.event).to eq(event)
      expect(result.slot).to be_reserved
      expect(event.response_slots.active.count).to eq(1)
    end

    it 'reuses the existing slot for a duplicate trigger' do
      first = window.reserve!(event: event, trigger_message_id: message.id)

      expect do
        second = window.reserve!(event: event, trigger_message_id: message.id)
        expect(second.status).to eq(:reused)
        expect(second.slot).to eq(first.slot)
      end.not_to change(AiAgentResponseSlot, :count)
    end

    it 're-reserves a released slot while capacity remains' do
      first = window.reserve!(event: event, trigger_message_id: message.id)
      window.release!(event: event, slot: first.slot)

      second = window.reserve!(event: event, trigger_message_id: message.id)

      expect(second.status).to eq(:reserved)
      expect(second.slot).to eq(first.slot)
      expect(first.slot.reload).to be_reserved
      expect(event.response_slots.active.count).to eq(1)
    end

    it 'returns reused for a duplicate of a now-reserved retry' do
      first = window.reserve!(event: event, trigger_message_id: message.id)
      window.release!(event: event, slot: first.slot)
      window.reserve!(event: event, trigger_message_id: message.id)

      third = window.reserve!(event: event, trigger_message_id: message.id)

      expect(third.status).to eq(:reused)
      expect(third.slot).to eq(first.slot)
    end

    it 're-reserves a released slot and counts it active when capacity remains' do
      create_consumed_slots(49)
      released = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message, status: :released)

      result = window.reserve!(event: event, trigger_message_id: message.id)

      expect(result.status).to eq(:reserved)
      expect(result.slot).to eq(released)
      expect(released.reload).to be_reserved
      expect(event.response_slots.active.count).to eq(50)
    end

    it 'never reuses a released slot when another trigger filled the window' do
      create_consumed_slots(50)
      released = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message, status: :released)

      result = window.reserve!(event: event, trigger_message_id: message.id)

      expect(result.status).to eq(:exhausted)
      expect(result.slot).to eq(released)
      expect(released.reload).to be_released
      expect(event.response_slots.active.count).to eq(50)
    end

    it 'returns exhausted for a trigger whose terminal handoff was already delivered' do
      create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message, status: :handed_off)

      result = window.reserve!(event: event, trigger_message_id: message.id)

      expect(result.status).to eq(:exhausted)
      expect(result.slot).to be_nil
    end

    it 'exhausts when the active count already reached the limit' do
      create_consumed_slots(50)

      result = window.reserve!(event: event, trigger_message_id: message.id)

      expect(result.status).to eq(:exhausted)
      expect(AiAgentResponseSlot.where(ai_agent_usage_event: event).count).to eq(50)
    end

    it 'allows the 50th response' do
      create_consumed_slots(49)

      result = window.reserve!(event: event, trigger_message_id: message.id)

      expect(result.status).to eq(:reserved)
      expect(event.response_slots.active.count).to eq(50)
    end

    it 'allows the same trigger on a different event' do
      other_event = create(:ai_agent_usage_event, account: account, ai_agent: ai_agent, contact: contact, conversation: conversation,
                                                  status: :reserved)

      expect do
        window.reserve!(event: event, trigger_message_id: message.id)
        described_class.new(ai_agent: ai_agent, message: message).reserve!(event: other_event, trigger_message_id: message.id)
      end.not_to raise_error
    end
  end

  describe '#consume!' do
    it 'transitions a reserved slot to consumed' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message)

      window.consume!(event: event, slot: slot)

      expect(slot.reload).to be_consumed
    end

    it 'counts a released slot retried to success' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message, status: :released)

      window.consume!(event: event, slot: slot)

      expect(slot.reload).to be_consumed
    end

    it 'returns :consumed when a reserved slot becomes consumed' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message)

      expect(window.consume!(event: event, slot: slot)).to eq(:consumed)
      expect(slot.reload).to be_consumed
    end

    it 'returns :consumed idempotently for an already consumed slot' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message, status: :consumed)

      expect(window.consume!(event: event, slot: slot)).to eq(:consumed)
      expect(slot.reload).to be_consumed
    end

    it 'reclaims and consumes a released retry only while capacity remains' do
      account.update!(ai_agent_response_limit_per_window: 2)
      small_window = described_class.new(ai_agent: ai_agent, message: message)
      first = small_window.reserve!(event: event, trigger_message_id: message.id)
      small_window.release!(event: event, slot: first.slot)
      create_consumed_slots(1)

      result = small_window.consume!(event: event, slot: first.slot)

      expect(result).to eq(:consumed)
      expect(first.slot.reload).to be_consumed
      expect(event.response_slots.consumed.count).to eq(2)
    end

    it 'never consumes a released slot once other triggers filled the window' do
      account.update!(ai_agent_response_limit_per_window: 2)
      small_window = described_class.new(ai_agent: ai_agent, message: message)
      first = small_window.reserve!(event: event, trigger_message_id: message.id)
      small_window.release!(event: event, slot: first.slot)
      create_consumed_slots(2)

      result = small_window.consume!(event: event, slot: first.slot)

      expect(result).to eq(:exhausted)
      expect(first.slot.reload).to be_released
      expect(event.response_slots.consumed.count).to eq(2)
    end

    it 'never transitions a handed_off marker' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message, status: :handed_off)

      window.consume!(event: event, slot: slot)

      expect(slot.reload).to be_handed_off
    end

    it 'is a no-op for an already consumed slot' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message, status: :consumed)

      expect { window.consume!(event: event, slot: slot) }.not_to(change { slot.reload.updated_at })
    end
  end

  describe 'warning delivery' do
    it 'persists exactly one deterministic public warning at the threshold' do
      create_consumed_slots(44)
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message)

      expect do
        window.consume!(event: event, slot: slot)
      end.to change { conversation.messages.where(private: false, sender: ai_agent.agent_bot).count }.by(1)

      warning = conversation.messages.where(private: false, sender: ai_agent.agent_bot).last
      expect(warning.content).to eq(I18n.t('ai_agents.response_limit_warning', locale: :en))
      expect(warning.content_attributes).to eq(
        'ai_agent' => { 'system_notice' => { 'type' => 'response_limit_warning', 'limit' => 50, 'remaining' => 5 } }
      )
      expect(warning.content_attributes.dig('ai_agent', 'trigger_message_id')).to be_nil
      expect(event.reload.response_limit_warning_sent).to be(true)
      expect(warning.public_content_attributes).not_to have_key('ai_agent')
    end

    it 'uses the account locale for the warning copy' do
      account.update!(locale: :tr)
      create_consumed_slots(44)
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message)

      window.consume!(event: event, slot: slot)

      warning = conversation.messages.where(private: false, sender: ai_agent.agent_bot).last
      expect(warning.content).to eq(I18n.t('ai_agents.response_limit_warning', locale: :tr))
    end

    it 'does not warn again after the flag is set' do
      create_consumed_slots(44)
      slot45 = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message)
      slot46 = create(:ai_agent_response_slot, ai_agent_usage_event: event, status: :reserved)

      window.consume!(event: event, slot: slot45)
      expect { window.consume!(event: event, slot: slot46) }.not_to(change { conversation.messages.where(private: false).count })
    end

    it 'never warns for limits of 5 or less' do
      account.update!(ai_agent_response_limit_per_window: 5)
      small_window = described_class.new(ai_agent: ai_agent, message: message)
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message)

      small_window.consume!(event: event, slot: slot)

      expect(conversation.messages.where(private: false, sender: ai_agent.agent_bot)).to be_empty
    end

    it 'warns at the derived threshold for small limits above 5' do
      account.update!(ai_agent_response_limit_per_window: 6)
      small_window = described_class.new(ai_agent: ai_agent, message: message)
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message)

      small_window.consume!(event: event, slot: slot)

      expect(event.reload.response_limit_warning_sent).to be(true)
      expect(conversation.messages.where(private: false, sender: ai_agent.agent_bot).count).to eq(1)
    end
  end

  describe '#release!' do
    it 'releases a reserved slot' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message)

      window.release!(event: event, slot: slot)

      expect(slot.reload).to be_released
    end

    it 'is a no-op for released, consumed, and handed_off slots' do
      released = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message, status: :released)
      consumed = create(:ai_agent_response_slot, ai_agent_usage_event: event, status: :consumed)
      handed_off = create(:ai_agent_response_slot, ai_agent_usage_event: event, status: :handed_off)

      window.release!(event: event, slot: released)
      window.release!(event: event, slot: consumed)
      window.release!(event: event, slot: handed_off)

      expect(released.reload).to be_released
      expect(consumed.reload).to be_consumed
      expect(handed_off.reload).to be_handed_off
    end
  end

  describe '#exhausted_handoff!' do
    it 'delivers one public terminal message with the system-notice shape' do
      result = window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: message.id)

      expect(result).to be(true)
      expect(event.response_slots.find_by(trigger_message_id: message.id)).to be_handed_off

      public_message = conversation.messages.where(private: false, sender: ai_agent.agent_bot).last
      expect(public_message.content).to eq(I18n.t('ai_agents.response_limit_handoff_message', locale: :en))
      expect(public_message.content_attributes).to eq(
        'ai_agent' => { 'system_notice' => { 'type' => 'response_limit_handoff', 'limit' => 50 } }
      )
      expect(public_message.content_attributes.dig('ai_agent', 'trigger_message_id')).to be_nil
      expect(public_message.public_content_attributes).not_to have_key('ai_agent')
    end

    it 'persists a diagnostic private note and marks the conversation as handed off' do
      window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: message.id)

      private_note = conversation.messages.where(private: true).last
      expect(private_note.content).to include('limit: 50', 'used: 0', 'Window resets at')
      expect(private_note.content).to include('Reason: ai_response_limit_exhausted')

      attrs = conversation.reload.additional_attributes
      expect(attrs['ai_handoff_completed']).to be(true)
      expect(attrs['ai_handoff_reason']).to eq('ai_response_limit_exhausted')
      expect(attrs['ai_handoff_message_id']).to eq(message.id)
      expect(attrs['ai_response_limit_exhausted']).to be(true)
      expect(conversation).to be_open
    end

    it 'is exactly-once per trigger' do
      expect(window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: message.id)).to be(true)

      expect do
        second = window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: message.id)
        expect(second).to be(false)
      end.not_to change(Message, :count)
    end

    it 'does not deliver again for another trigger in the same handed-off conversation' do
      window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: message.id)
      second_trigger = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: contact)

      expect do
        expect(window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: second_trigger.id)).to be(false)
      end.not_to change(Message, :count)
    end

    it 'delivers per conversation for the same shared event' do
      other_conversation = create(:conversation, account: account, inbox: inbox, contact: contact, status: 'pending')
      other_trigger = create(:message, account: account, inbox: inbox, conversation: other_conversation, message_type: 'incoming',
                                       sender: contact)

      window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: message.id)

      expect do
        expect(window.exhausted_handoff!(event: event, conversation: other_conversation, trigger_message_id: other_trigger.id)).to be(true)
      end.to change { other_conversation.messages.count }.by(2)

      expect(other_conversation.reload.additional_attributes['ai_handoff_completed']).to be(true)
    end

    it 'uses the account locale for terminal copy' do
      account.update!(locale: :tr)

      window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: message.id)

      public_message = conversation.messages.where(private: false, sender: ai_agent.agent_bot).last
      expect(public_message.content).to eq(I18n.t('ai_agents.response_limit_handoff_message', locale: :tr))
      expect(conversation.messages.where(private: true).last.content).to include('sınır: 50')
    end
  end

  describe 'concurrency' do
    self.use_transactional_tests = false

    after do
      if account
        AiAgentResponseSlot.where(ai_agent_usage_event_id: event&.id).delete_all if event
        AiAgentUsageEvent.where(account_id: account.id).delete_all
        Conversation.where(account_id: account.id).delete_all
        Message.where(account_id: account.id).delete_all
        Contact.where(account_id: account.id).delete_all
        Inbox.where(account_id: account.id).delete_all
        ai_agent&.delete
        AgentBot.where(id: ai_agent.agent_bot_id).delete_all if ai_agent
        account.delete
      end
    end

    it 'never exceeds the limit when reservations race at the boundary' do
      create_consumed_slots(49)
      triggers = Array.new(3) do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: contact)
      end

      results = Concurrent::Array.new
      barrier = Concurrent::CyclicBarrier.new(3)

      threads = triggers.map do |trigger|
        Thread.new do
          barrier.wait
          results << window.reserve!(event: event, trigger_message_id: trigger.id).status
        end
      end

      unfinished = threads.reject { |thread| thread.join(30) }
      expect(unfinished).to be_empty
      threads.each(&:value)

      expect(results.count { |status| status == :reserved }).to eq(1)
      expect(results.count { |status| status == :exhausted }).to eq(2)
      expect(AiAgentResponseSlot.where(ai_agent_usage_event_id: event.id).count).to eq(50)
    end

    it 'lets only one of two concurrent released retries re-reserve at the boundary' do
      create_consumed_slots(49)
      released_triggers = Array.new(2) do
        trigger = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: contact)
        create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger, status: :released)
        trigger
      end

      results = Concurrent::Array.new
      barrier = Concurrent::CyclicBarrier.new(2)

      threads = released_triggers.map do |trigger|
        Thread.new do
          barrier.wait
          results << window.reserve!(event: event, trigger_message_id: trigger.id).status
        end
      end

      unfinished = threads.reject { |thread| thread.join(30) }
      expect(unfinished).to be_empty
      threads.each(&:value)

      expect(results.count { |status| status == :reserved }).to eq(1)
      expect(results.count { |status| status == :exhausted }).to eq(1)
      expect(event.response_slots.active.count).to eq(50)
      expect(AiAgentResponseSlot.where(ai_agent_usage_event_id: event.id, status: :released).count).to eq(1)
    end

    it 'creates a single slot row for concurrent duplicate reservations of the same trigger' do
      results = Concurrent::Array.new
      barrier = Concurrent::CyclicBarrier.new(2)

      threads = Array.new(2) do
        Thread.new do
          barrier.wait
          results << window.reserve!(event: event, trigger_message_id: message.id)
        end
      end

      unfinished = threads.reject { |thread| thread.join(30) }
      expect(unfinished).to be_empty
      threads.each(&:value)

      expect(results.map(&:status).sort).to eq(%i[reserved reused])
      expect(AiAgentResponseSlot.where(ai_agent_usage_event_id: event.id, trigger_message_id: message.id).count).to eq(1)
    end

    it 'delivers exactly one terminal for concurrent same-trigger handoffs' do
      barrier = Concurrent::CyclicBarrier.new(2)
      results = Concurrent::Array.new

      threads = Array.new(2) do
        Thread.new do
          barrier.wait
          results << window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: message.id)
        end
      end

      unfinished = threads.reject { |thread| thread.join(30) }
      expect(unfinished).to be_empty
      threads.each(&:value)

      expect(results.count(true)).to eq(1)
      expect(conversation.messages.where(private: false, sender: ai_agent.agent_bot).count).to eq(1)
      expect(conversation.messages.where(private: true).count).to eq(1)
      expect(AiAgentResponseSlot.where(ai_agent_usage_event_id: event.id, trigger_message_id: message.id).count).to eq(1)
    end

    it 'delivers exactly one public terminal for concurrent same-conversation boundary triggers' do
      create_consumed_slots(50)
      triggers = Array.new(2) do
        create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming', sender: contact)
      end
      barrier = Concurrent::CyclicBarrier.new(2)

      threads = triggers.map do |trigger|
        Thread.new do
          barrier.wait
          window.reserve!(event: event, trigger_message_id: trigger.id).status
          window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: trigger.id)
        end
      end

      unfinished = threads.reject { |thread| thread.join(30) }
      expect(unfinished).to be_empty
      threads.each(&:value)

      expect(conversation.messages.where(private: false, sender: ai_agent.agent_bot).count).to eq(1)
      expect(conversation.messages.where(private: true).count).to eq(1)
      expect(conversation.reload.additional_attributes['ai_handoff_completed']).to be(true)
    end

    it 'completes concurrent persist and terminal paths without deadlock' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: message)
      terminal_trigger = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: 'incoming',
                                          sender: contact)
      barrier = Concurrent::CyclicBarrier.new(2)
      results = Concurrent::Array.new

      threads = [
        Thread.new do
          barrier.wait
          conversation.reload.with_lock do
            window.consume!(event: event, slot: slot)
            results << :persisted
          end
        end,
        Thread.new do
          barrier.wait
          window.exhausted_handoff!(event: event, conversation: conversation, trigger_message_id: terminal_trigger.id)
          results << :terminal
        end
      ]

      unfinished = threads.reject { |thread| thread.join(30) }
      expect(unfinished).to be_empty
      threads.each(&:value)

      expect(results).to include(:persisted, :terminal)
      expect(slot.reload).to be_consumed
    end
  end
end
