class AiAgents::LiveProcessor
  HANDOFF_COMPLETED_KEY = 'ai_handoff_completed'.freeze

  def initialize(message:, adapter: nil)
    @message = message
    @adapter = adapter
  end

  def perform
    return unless eligible_message?
    return if handoff_completed?

    result = AiAgents::Orchestrator.new(
      ai_agent: ai_agent,
      messages: orchestrator_messages,
      mode: :live,
      conversation: conversation,
      trigger_message: message,
      adapter: adapter
    ).perform

    post_assistant_message!(result[:assistant_message]) unless handoff_result?(result)

    handoff_result?(result)
  end

  private

  attr_reader :message, :adapter

  def conversation
    message.conversation
  end

  def ai_agent
    @ai_agent ||= conversation.assignee_agent_bot&.ai_agent || conversation.inbox.agent_bot&.ai_agent
  end

  def eligible_message?
    ai_agent&.enabled? && eligible_customer_message?
  end

  def eligible_customer_message?
    message.incoming? && !message.private? && !message.activity? && !message.template? && !ai_generated_message?
  end

  def ai_generated_message?
    message.outgoing? && message.sender_type.in?(['AgentBot', 'Captain::Assistant'])
  end

  def handoff_completed?
    attrs = conversation.additional_attributes
    attrs.is_a?(Hash) && attrs[HANDOFF_COMPLETED_KEY] == true
  end

  def orchestrator_messages
    pending_messages.map do |entry|
      {
        role: entry.message_type == 'incoming' ? 'user' : 'assistant',
        content: entry.content_for_llm
      }
    end
  end

  def pending_messages
    conversation.messages
                .where(private: false, message_type: :incoming)
                .where('id > ?', latest_ai_boundary_id)
                .where(id: ..message.id)
                .order(:id)
                .reject { |entry| entry.content_for_llm.blank? }
  end

  def latest_ai_boundary_id
    latest_boundary_message&.id || 0
  end

  def latest_boundary_message
    conversation.messages
                .where(private: false, message_type: :outgoing, sender_type: 'AgentBot', sender_id: ai_agent.agent_bot_id)
                .reorder(id: :desc)
                .first
  end

  def post_assistant_message!(assistant_message)
    return if assistant_message.blank?

    Messages::MessageBuilder.new(nil, conversation.reload, assistant_message_params(assistant_message)).perform
  end

  def assistant_message_params(assistant_message)
    {
      content: assistant_message['content'] || assistant_message[:content],
      private: false,
      sender_type: 'AgentBot',
      sender_id: ai_agent.agent_bot_id
    }
  end

  def handoff_result?(result)
    result[:terminal_action] == 'handoff'
  end
end
