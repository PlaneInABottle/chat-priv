class Voice::AccountCallFinalizerJob < ApplicationJob
  queue_as :default

  def perform(account)
    Voice::AccountCallFinalizer.perform(account: account)
  end
end
