class AiAgentLearningListener < BaseListener
  def conversation_resolved(event)
    conversation, = extract_conversation_and_account(event)
    AiAgents::AutomaticLearningCapture.new(conversation: conversation).perform
  rescue StandardError => e
    Rails.logger.error(
      "[AiAgentLearningListener] conversation_id=#{conversation&.id} #{e.class}: #{e.message}"
    )
  end
end
