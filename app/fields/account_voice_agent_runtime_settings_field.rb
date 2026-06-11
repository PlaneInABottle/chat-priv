# frozen_string_literal: true

class AccountVoiceAgentRuntimeSettingsField < Administrate::Field::Base
  def to_s
    "#{voice_agents.count} voice #{'agent'.pluralize(voice_agents.count)}"
  end

  def html_name
    "#{resource.class.name.underscore}[#{attribute}]"
  end

  def voice_agents
    @voice_agents ||= resource.voice_agents.order(:created_at, :id)
  end
end
