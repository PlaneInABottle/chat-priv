class Voice::AccountCallFinalizer
  def self.perform(account:)
    new(account: account).perform
  end

  def initialize(account:)
    @account = account
  end

  def perform
    active_livekit_calls.find_each do |call|
      Voice::CallFinalizer.perform!(call: call, status: 'completed', end_reason: 'voice_ai_disabled')
    rescue StandardError => e
      Rails.logger.warn("voice call finalization failed account_id=#{account.id} call_id=#{call.id} error=#{e.class.name}: #{e.message}")
    end
  end

  private

  attr_reader :account

  def active_livekit_calls
    account.calls.livekit.active
  end
end
