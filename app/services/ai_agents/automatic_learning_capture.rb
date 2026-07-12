# frozen_string_literal: true

class AiAgents::AutomaticLearningCapture
  MAX_REPLY_CANDIDATES = 20

  def initialize(conversation:)
    @conversation = conversation
  end

  def perform
    return unless eligible?
    return if ai_agent.learning_suggestions.exists?(conversation: conversation)
    return unless human_reply

    AiAgents::LearningSuggestionCreator.new(
      message: human_reply,
      submitted_by: human_reply.sender,
      ai_agent: ai_agent
    ).perform
  rescue AiAgents::LearningSuggestionCreator::InvalidCandidate, AiImprovements::Usage::Exhausted
    nil
  end

  private

  attr_reader :conversation

  delegate :account, to: :conversation

  def eligible?
    account.ai_agent_enabled? && conversation.resolved? && handoff_attributes['ai_handoff_completed'] == true &&
      ai_agent&.auto_learning_enabled?
  end

  def ai_agent
    @ai_agent ||= account.ai_agents.find_by(id: handoff_attributes['ai_handoff_by_ai_agent_id'])
  end

  def human_reply
    @human_reply ||= conversation.messages
                                 .outgoing
                                 .where(private: false, sender_type: 'User')
                                 .where('id > ?', handoff_attributes['ai_handoff_message_id'].to_i)
                                 .reorder(id: :desc)
                                 .limit(MAX_REPLY_CANDIDATES)
                                 .detect { |message| !message.deleted && message.content_for_llm.to_s.strip.present? }
  end

  def handoff_attributes
    @handoff_attributes ||= conversation.additional_attributes.to_h.deep_stringify_keys
  end
end
