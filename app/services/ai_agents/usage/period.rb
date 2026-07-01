# frozen_string_literal: true

class AiAgents::Usage::Period
  def initialize(account:, now: Time.current)
    @account = account
    @now = now
  end

  def start_at
    @start_at ||= zoned_now.beginning_of_month.utc
  end

  def end_at
    @end_at ||= zoned_now.next_month.beginning_of_month.utc
  end

  def reset_at
    end_at
  end

  def timezone
    @timezone ||= if account.reporting_timezone.present?
                    ActiveSupport::TimeZone[account.reporting_timezone] || Time.zone
                  else
                    Time.zone
                  end
  end

  private

  attr_reader :account, :now

  def zoned_now
    @zoned_now ||= now.in_time_zone(timezone)
  end
end
