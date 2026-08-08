# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiAgents::ReplyPolicy do
  describe '.can_reply?' do
    context 'when the conversation is pending' do
      it 'allows AI replies when the handoff flag is not set' do
        conversation = build(:conversation, status: :pending)

        expect(described_class.can_reply?(conversation)).to be(true)
      end

      it 'blocks AI replies once the handoff flag is set' do
        conversation = build(:conversation, status: :pending, additional_attributes: { 'ai_handoff_completed' => true })

        expect(described_class.can_reply?(conversation)).to be(false)
      end

      it 'allows AI replies when additional_attributes is nil' do
        conversation = build(:conversation, status: :pending, additional_attributes: nil)

        expect(described_class.can_reply?(conversation)).to be(true)
      end

      it 'allows AI replies when additional_attributes is not a hash' do
        conversation = build(:conversation, status: :pending, additional_attributes: 'not-a-hash')

        expect(described_class.can_reply?(conversation)).to be(true)
      end
    end

    context 'when the conversation is not pending' do
      it 'blocks AI replies for open conversations' do
        conversation = build(:conversation, status: :open)

        expect(described_class.can_reply?(conversation)).to be(false)
      end

      it 'blocks AI replies for resolved conversations' do
        conversation = build(:conversation, status: :resolved)

        expect(described_class.can_reply?(conversation)).to be(false)
      end

      it 'blocks AI replies for snoozed conversations' do
        conversation = build(:conversation, status: :snoozed)

        expect(described_class.can_reply?(conversation)).to be(false)
      end
    end
  end

  describe '.handoff_completed?' do
    it 'is false when additional_attributes is nil' do
      conversation = build(:conversation, additional_attributes: nil)

      expect(described_class.handoff_completed?(conversation)).to be(false)
    end

    it 'is false when additional_attributes is not a hash' do
      conversation = build(:conversation, additional_attributes: 'not-a-hash')

      expect(described_class.handoff_completed?(conversation)).to be(false)
    end

    it 'is false when the handoff flag is absent' do
      conversation = build(:conversation, additional_attributes: { 'unrelated_key' => true })

      expect(described_class.handoff_completed?(conversation)).to be(false)
    end

    it 'is true when the handoff flag is set to true' do
      conversation = build(:conversation, additional_attributes: { 'ai_handoff_completed' => true })

      expect(described_class.handoff_completed?(conversation)).to be(true)
    end
  end
end
