# frozen_string_literal: true

class AccountAiImprovementSettingsField < Administrate::Field::Base
  def html_name
    "#{resource.class.name.underscore}[#{attribute}]"
  end

  def to_s
    resource.ai_improvement_monthly_credit_limit.to_s
  end
end
