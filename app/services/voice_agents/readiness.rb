# frozen_string_literal: true

class VoiceAgents::Readiness
  def initialize(voice_agent)
    @voice_agent = voice_agent
  end

  def payload
    {
      can_publish: checks.select { |check| check[:blocking] }.all? { |check| check[:complete] },
      checks: checks
    }
  end

  private

  attr_reader :voice_agent

  def checks
    @checks ||= [
      check('greeting', voice_agent.greeting.present?, 'Add a greeting for callers.'),
      check('instructions', voice_agent.prompt.present?, 'Add instructions for how the assistant should respond.'),
      check('inbox', voice_agent.voice_inbox_settings.exists?, 'Connect at least one call inbox.'),
      check('test', voice_agent.last_tested_at.present?, 'Complete a successful browser test call.'),
      check('phone', active_phone_number?, 'No production phone number is connected yet.', blocking: false)
    ]
  end

  def active_phone_number?
    VoiceNumber.active.joins(:voice_inbox_setting)
               .exists?(voice_inbox_settings: { voice_agent_id: voice_agent.id })
  end

  def check(key, complete, message, blocking: true)
    { key: key, complete: complete, blocking: blocking, message: message }
  end
end
