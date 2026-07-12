# frozen_string_literal: true

class AiAgents::LearningSuggestionCreator
  class InvalidCandidate < StandardError; end

  def initialize(message:, submitted_by:, ai_agent: nil)
    @message = message
    @submitted_by = submitted_by
    @explicit_ai_agent = ai_agent
  end

  def perform
    validate_candidate!
    existing = ai_agent.learning_suggestions.find_by(source_message: message)
    return existing if existing

    improvement_limiter.ensure_available!
    suggestion = ai_agent.learning_suggestions.create!(suggestion_attributes)
    AiAgents::LearningSuggestionJob.perform_later(suggestion)
    suggestion
  rescue ActiveRecord::RecordNotUnique
    ai_agent.learning_suggestions.find_by!(source_message: message)
  end

  private

  attr_reader :message, :submitted_by, :explicit_ai_agent

  delegate :conversation, :account, to: :message

  def validate_candidate!
    raise InvalidCandidate, 'AI assistants are not enabled for this account.' unless account.ai_agent_enabled?
    raise InvalidCandidate, 'Connect an AI assistant to this inbox first.' unless ai_agent&.account_id == account.id
    raise InvalidCandidate, 'Only public human replies with text can be suggested.' unless human_text_reply?
    raise InvalidCandidate, 'No earlier customer question was found for this reply.' unless customer_message
  end

  def human_text_reply?
    message.outgoing? && !message.private? && message.sender_type == 'User' && human_answer.present? && !message.deleted
  end

  def ai_agent
    @ai_agent ||= explicit_ai_agent || conversation.assignee_agent_bot&.ai_agent || message.inbox.agent_bot&.ai_agent
  end

  def customer_message
    @customer_message ||= conversation.messages
                                      .incoming
                                      .where(private: false)
                                      .where.not(content: [nil, ''])
                                      .where(
                                        'created_at < :created_at OR (created_at = :created_at AND id < :id)',
                                        created_at: message.created_at,
                                        id: message.id
                                      )
                                      .reorder(created_at: :desc, id: :desc)
                                      .first
  end

  def human_answer
    @human_answer ||= message.content_for_llm.to_s.strip.presence
  end

  def suggestion_attributes
    {
      account: account,
      conversation: conversation,
      source_message: message,
      submitted_by: submitted_by,
      status: :pending,
      customer_message: customer_message.content_for_llm.to_s.strip.truncate(10_000),
      human_answer: human_answer.truncate(10_000)
    }
  end

  def improvement_limiter
    @improvement_limiter ||= AiImprovements::Usage::Limiter.new(
      account: account,
      operation: 'learning',
      ai_agent: ai_agent,
      initiated_by: submitted_by
    )
  end
end
