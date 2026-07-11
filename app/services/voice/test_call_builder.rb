class Voice::TestCallBuilder
  def self.perform!(account:, inbox:, voice_agent: nil, caller_name: nil, caller_number: nil, initiated_by: nil)
    new(
      account: account,
      inbox: inbox,
      voice_agent: voice_agent,
      caller_name: caller_name,
      caller_number: caller_number,
      initiated_by: initiated_by
    ).perform!
  end

  def initialize(account:, inbox:, voice_agent: nil, caller_name: nil, caller_number: nil, initiated_by: nil)
    @account = account
    @inbox = inbox
    @voice_agent = voice_agent
    @caller_name = caller_name.presence || 'Test caller'
    @caller_number = caller_number.presence || '+900000000000'
    @initiated_by = initiated_by
  end

  def perform!
    raise ArgumentError, 'Voice MVP test calls require an API inbox' unless inbox.api?
    Voice::Usage::Admission.check!(account: account, test_call: true)

    setting = assigned_setting!
    room_name = room_name_for(setting)
    @improvement_usage_event = reserve_improvement_credit(room_name, setting.voice_agent)
    call = build_call!(setting, room_name)
    @improvement_usage_event.update!(call: call)
    start_call!(call, room_name)
    call
  rescue StandardError => e
    improvement_limiter.release!(@improvement_usage_event) if @improvement_usage_event
    finalize_failed_call(call, e)
    raise
  end

  private

  attr_reader :account, :inbox, :voice_agent, :caller_name, :caller_number, :initiated_by

  def assigned_setting!
    raise ArgumentError, 'Voice agent must belong to this account.' if voice_agent && voice_agent.account_id != account.id

    setting = account.voice_inbox_setting_for(inbox: inbox)
    expected_voice_agent = voice_agent || setting&.voice_agent
    unless expected_voice_agent && setting&.voice_agent_id == expected_voice_agent.id
      raise ArgumentError, 'Assign this inbox to the selected voice agent before starting a test call.'
    end

    setting
  end

  def room_name_for(setting)
    "#{setting.livekit_room_prefix}-#{SecureRandom.hex(6)}"
  end

  def build_call!(setting, room_name)
    Call.create!(
      account: account,
      inbox: inbox,
      provider: :livekit,
      direction: :incoming,
      status: 'ringing',
      provider_call_id: room_name,
      meta: {
        'initiated_at' => Time.zone.now.to_i,
        'from_number' => caller_number
      }.merge(call_meta(setting, room_name))
    )
  end

  def call_meta(setting, room_name)
    {
      'contact_name' => caller_name,
      'livekit_room_name' => room_name,
      'voice_inbox_setting_id' => setting.id,
      'voice_agent_id' => setting.voice_agent_id,
      'voice_agent_draft_fingerprint' => setting.voice_agent.draft_fingerprint,
      'ai_improvement_usage_event_id' => @improvement_usage_event&.id,
      'ai_improvement_max_duration_seconds' => improvement_duration_limit_seconds,
      'test_call' => true,
      'test_call_source' => 'voice_ai_settings',
      'test_call_initiated_by_user_id' => initiated_by&.id,
      'handoff_status' => 'none',
      'ai_status' => 'waiting'
    }.compact
  end

  def reserve_improvement_credit(room_name, resolved_voice_agent)
    improvement_limiter(resolved_voice_agent).reserve_or_raise!(
      unit_type: 'audio_seconds',
      credits: reservable_test_credits,
      idempotency_key: "voice_test_call:#{room_name}",
      metadata: { 'livekit_room_name' => room_name }
    )
  end

  def reservable_test_credits
    payload = AiImprovements::Usage::Summary.new(account: account).payload
    return maximum_test_credits if payload[:unlimited]

    [payload[:remaining_credits], maximum_test_credits].min.clamp(1, maximum_test_credits)
  end

  def maximum_test_credits
    @maximum_test_credits ||= AiImprovements::Usage::Meter.credits_for(
      unit_type: 'audio_seconds',
      units: account.voice_ai_max_call_duration_minutes.minutes.to_i
    )
  end

  def improvement_duration_limit_seconds
    @improvement_usage_event&.credits.to_i * AiImprovements::Usage::Meter::UNITS_PER_CREDIT.fetch('audio_seconds')
  end

  def improvement_limiter(resolved_voice_agent = voice_agent)
    @improvement_limiter ||= AiImprovements::Usage::Limiter.new(
      account: account,
      operation: 'voice_test',
      voice_agent: resolved_voice_agent,
      initiated_by: initiated_by
    )
  end

  def start_call!(call, room_name)
    call.update!(livekit_room_name: room_name, started_at: Time.zone.now, status: 'in_progress')
    dispatch_agent!(call)
    schedule_improvement_budget_finalization(call)
    Voice::CallMessageBuilder.new(call).update_status!(status: call.status)
  end

  def schedule_improvement_budget_finalization(call)
    Voice::TestCallImprovementBudgetJob.set(wait: Voice::TestCallImprovementBudgetJob::PARTICIPANT_JOIN_GRACE).perform_later(call)
  end

  def dispatch_agent!(call)
    result = Voice::Livekit::AgentDispatchService.perform(
      call: call,
      metadata: dispatch_metadata(call)
    )
    call.update!(meta: (call.meta || {}).merge('voice_agent_dispatch' => result))
  end

  def dispatch_metadata(call)
    {
      account_id: account.id,
      inbox_id: inbox.id,
      call_id: call.id,
      conversation_id: nil,
      provider_call_id: call.provider_call_id,
      livekit_room_name: call.livekit_room_name,
      voice_agent_id: call.meta['voice_agent_id']
    }.compact
  end

  def finalize_failed_call(call, error)
    return unless call&.persisted? && !call.terminal?

    Rails.logger.warn("voice test call start failed call_id=#{call.id} error=#{error.class.name}: #{error.message}")
    Voice::CallFinalizer.perform!(call: call, status: 'failed', end_reason: 'test_call_start_failed')
  rescue StandardError => e
    Rails.logger.warn("voice test call cleanup failed call_id=#{call.id} error=#{e.class.name}: #{e.message}")
  end
end
