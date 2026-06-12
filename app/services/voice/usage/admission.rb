class Voice::Usage::Admission
  Error = Class.new(ArgumentError)

  Result = Struct.new(:status, :summary, keyword_init: true) do
    def allowed?
      status == :allowed
    end

    def error_code
      status.to_s
    end

    def error_message
      case status
      when :voice_ai_disabled
        I18n.t('errors.voice.usage.disabled')
      when :monthly_limit_exhausted
        I18n.t('errors.voice.usage.monthly_limit_exhausted')
      when :concurrent_limit_reached
        I18n.t('errors.voice.usage.concurrent_limit_reached')
      else
        I18n.t('errors.voice.usage.rejected')
      end
    end
  end

  def self.check!(account:, test_call: false, now: Time.current)
    result = new(account: account, test_call: test_call, now: now).call
    raise Error, result.error_message unless result.allowed?

    result
  end

  def initialize(account:, test_call: false, now: Time.current)
    @account = account
    @test_call = test_call
    @now = now
  end

  def call
    return result(:voice_ai_disabled) unless account.voice_ai_enabled?
    return result(:allowed) if test_call
    return result(:monthly_limit_exhausted) if monthly_limit_exhausted?
    return result(:concurrent_limit_reached) if concurrent_limit_reached?

    result(:allowed)
  end

  private

  attr_reader :account, :test_call, :now

  def monthly_limit_exhausted?
    return false if usage_summary.unlimited?

    usage_summary.remaining_minutes.to_i <= 0
  end

  def concurrent_limit_reached?
    limit = account.voice_ai_concurrent_call_limit
    return false if limit.zero?

    usage_summary.active_calls >= limit
  end

  def usage_summary
    @usage_summary ||= Voice::Usage::Summary.new(account: account, now: now)
  end

  def summary
    @summary ||= usage_summary.payload
  end

  def result(status)
    Result.new(status: status, summary: summary)
  end
end
