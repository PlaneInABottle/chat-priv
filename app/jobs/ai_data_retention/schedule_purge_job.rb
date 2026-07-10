# frozen_string_literal: true

class AiDataRetention::SchedulePurgeJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Account.find_each do |account|
      AiDataRetention::PurgeAccountJob.perform_later(account.id)
    end
  end
end
