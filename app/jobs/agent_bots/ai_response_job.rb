class AgentBots::AiResponseJob < ApplicationJob
  queue_as :high

  def perform(message)
    AiAgents::LiveProcessor.new(message: message).perform
  end
end
