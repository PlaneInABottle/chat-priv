module AiAgents
  class LiveProcessor
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

      result[:terminal_action] == 'handoff'
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
      return false unless ai_agent&.enabled?
      return false unless message.incoming?
      return false if message.private?
      return false if message.activity?
      return false if message.template?
      return false if ai_generated_message?

      true
    end

    def ai_generated_message?
      message.outgoing? && message.sender_type.in?(['AgentBot', 'Captain::Assistant'])
    end

    def handoff_completed?
      attrs = conversation.additional_attributes
      attrs.is_a?(Hash) && attrs[HANDOFF_COMPLETED_KEY] == true
    end

    def orchestrator_messages
      recent_messages.map do |entry|
        {
          role: entry.message_type == 'incoming' ? 'user' : 'assistant',
          content: entry.content_for_llm
        }
      end
    end

    def recent_messages
      conversation.messages
                  .where(private: false, message_type: %i[incoming outgoing])
                  .reject { |entry| entry.content_for_llm.blank? }
                  .last(10)
    end
  end
end
