# frozen_string_literal: true

class AccountAiAgentSettingsField < Administrate::Field::Base
  def to_s
    data.to_s
  end

  def html_name
    "#{resource.class.name.underscore}[#{attribute}]"
  end
end
