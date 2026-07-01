class AgentBots::AiResponseJob < ApplicationJob
  queue_as :high

  def perform(message, buffer_token = nil)
    return perform_immediately(message) if buffer_token.nil?

    return unless AiAgents::ResponseBuffer.claim!(message, buffer_token)

    begin
      perform_immediately(message)
    rescue StandardError
      AiAgents::ResponseBuffer.release!(message, buffer_token)
      raise
    end

    AiAgents::ResponseBuffer.complete!(message, buffer_token)
  end

  private

  def perform_immediately(message)
    AiAgents::LiveProcessor.new(message: message).perform
  end
end
