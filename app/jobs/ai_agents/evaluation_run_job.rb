# frozen_string_literal: true

class AiAgents::EvaluationRunJob < ApplicationJob
  queue_as :low

  def perform(run)
    AiAgents::EvaluationRunner.new(run: run).perform
  end
end
