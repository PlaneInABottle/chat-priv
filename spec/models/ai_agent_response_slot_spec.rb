# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgentResponseSlot do
  let(:event) { create(:ai_agent_usage_event) }
  let(:trigger_message) { create(:message, account: event.account, conversation: event.conversation, sender: event.contact) }
  let(:second_trigger) { create(:message, account: event.account, conversation: event.conversation, sender: event.contact) }
  let(:third_trigger) { create(:message, account: event.account, conversation: event.conversation, sender: event.contact) }

  describe 'status enum' do
    it 'defines the reserved/consumed/released/handed_off lifecycle' do
      expect(described_class.statuses).to eq(
        'reserved' => 0,
        'consumed' => 1,
        'released' => 2,
        'handed_off' => 3
      )
    end
  end

  describe 'associations' do
    it 'belongs to the usage event and the trigger message' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message)

      expect(slot.ai_agent_usage_event).to eq(event)
      expect(slot.trigger_message).to eq(trigger_message)
      expect(event.response_slots).to include(slot)
    end

    it 'destroys slots when the usage event is destroyed' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message)

      event.destroy!

      expect(described_class.exists?(slot.id)).to be(false)
    end

    it 'cascades at the database level when the usage event is deleted' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message)

      AiAgentUsageEvent.where(id: event.id).delete_all

      expect(described_class.exists?(slot.id)).to be(false)
    end

    it 'cascades at the database level when the trigger message is deleted' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message)

      Message.where(id: trigger_message.id).delete_all

      expect(described_class.exists?(slot.id)).to be(false)
    end
  end

  describe 'uniqueness' do
    it 'enforces a unique (event, trigger message) pair at the database level' do
      create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message)

      expect do
        create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it 'allows the same trigger message on a different event' do
      other_event = create(:ai_agent_usage_event, account: event.account, contact: event.contact,
                                                  conversation: event.conversation)

      expect do
        create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message)
        create(:ai_agent_response_slot, ai_agent_usage_event: other_event, trigger_message: trigger_message)
      end.not_to raise_error
    end
  end

  describe 'ownership validation' do
    it 'rejects a trigger message from another account' do
      other_account_message = create(:message)

      slot = build(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: other_account_message)

      expect(slot).not_to be_valid
      expect(slot.errors[:trigger_message]).to include('must belong to account')
    end

    it 'accepts a trigger message from the event account' do
      slot = build(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message)

      expect(slot).to be_valid
    end
  end

  describe 'scopes' do
    it 'returns reserved and consumed slots as active' do
      reserved = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message, status: :reserved)
      consumed = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: second_trigger, status: :consumed)
      released = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: third_trigger, status: :released)

      expect(described_class.active).to include(reserved, consumed)
      expect(described_class.active).not_to include(released)
    end

    it 'filters consumed slots' do
      consumed = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message, status: :consumed)
      create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: second_trigger, status: :reserved)

      expect(described_class.consumed).to eq([consumed])
    end

    it 'filters slots by trigger message' do
      slot = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: trigger_message)
      other = create(:ai_agent_response_slot, ai_agent_usage_event: event, trigger_message: second_trigger, status: :consumed)

      expect(described_class.for_trigger(trigger_message.id)).to eq([slot])
      expect(described_class.for_trigger(other.trigger_message_id)).to eq([other])
    end
  end
end
