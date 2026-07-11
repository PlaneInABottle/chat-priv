# frozen_string_literal: true

class AiImprovements::Usage::Exhausted < StandardError
  attr_reader :summary

  def initialize(summary)
    @summary = summary
    super(I18n.t('errors.ai_improvement_usage.exhausted'))
  end
end
