class Voice::Livekit::ReconcileStaleCallsJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    Voice::Livekit::StaleCallFinalizer.perform!
  end
end
