# frozen_string_literal: true

class AiAgents::Readiness
  def initialize(ai_agent)
    @ai_agent = ai_agent
  end

  def payload
    {
      can_publish: checks.select { |check| check[:blocking] }.all? { |check| check[:complete] },
      checks: checks
    }
  end

  private

  attr_reader :ai_agent

  def checks
    @checks ||= [
      check('instructions', ai_agent.prompt.present?, 'Add instructions for how the assistant should respond.'),
      # `any?` reuses an already preloaded inboxes association; `exists?` would always hit the
      # database and turn the assistants listing into an N+1.
      check('inbox', ai_agent.agent_bot&.inboxes&.any? || false, 'Connect at least one inbox.'),
      check('test', ai_agent.draft_tested?, 'Complete a successful test conversation for the current draft.', blocking: false)
    ]
  end

  def check(key, complete, message, blocking: true)
    { key: key, complete: complete, blocking: blocking, message: message }
  end
end
