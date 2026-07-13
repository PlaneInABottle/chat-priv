# frozen_string_literal: true

class AiAgents::Readiness
  def initialize(ai_agent)
    @ai_agent = ai_agent
  end

  def payload
    {
      can_publish: checks.all? { |check| check[:complete] },
      checks: checks
    }
  end

  private

  attr_reader :ai_agent

  def checks
    @checks ||= [
      check('instructions', ai_agent.prompt.present?, 'Add instructions for how the assistant should respond.'),
      check('inbox', ai_agent.agent_bot&.inboxes&.exists?, 'Connect at least one inbox.')
    ]
  end

  def check(key, complete, message)
    { key: key, complete: complete, blocking: true, message: message }
  end
end
