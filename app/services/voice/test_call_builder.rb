class Voice::TestCallBuilder
  def self.perform!(account:, inbox:, caller_name: nil, caller_number: nil)
    new(account: account, inbox: inbox, caller_name: caller_name, caller_number: caller_number).perform!
  end

  def initialize(account:, inbox:, caller_name: nil, caller_number: nil)
    @account = account
    @inbox = inbox
    @caller_name = caller_name.presence || 'Test caller'
    @caller_number = caller_number.presence || '+900000000000'
  end

  def perform!
    raise ArgumentError, 'Voice MVP test calls require an API inbox' unless inbox.api?

    setting = ensure_setting!
    room_name = room_name_for(setting)
    call = build_call!(setting, room_name)
    start_call!(call, room_name)
    call
  end

  private

  attr_reader :account, :inbox, :caller_name, :caller_number

  def ensure_setting!
    account.voice_inbox_settings.find_or_create_by!(inbox: inbox) do |setting|
      setting.status = 'test_only'
      setting.greeting = 'Merhaba, size nasil yardimci olabilirim?'
    end
  end

  def room_name_for(setting)
    "#{setting.livekit_room_prefix}-#{SecureRandom.hex(6)}"
  end

  def build_call!(setting, room_name)
    Voice::InboundCallBuilder.perform!(
      inbox: inbox,
      from_number: caller_number,
      call_sid: room_name,
      provider: :livekit,
      extra_meta: call_meta(setting, room_name)
    )
  end

  def call_meta(setting, room_name)
    {
      'contact_name' => caller_name,
      'livekit_room_name' => room_name,
      'voice_inbox_setting_id' => setting.id,
      'ai_agent_id' => setting.ai_agent_id,
      'handoff_status' => 'none',
      'ai_status' => 'waiting'
    }
  end

  def start_call!(call, room_name)
    call.update!(livekit_room_name: room_name, started_at: Time.zone.now, status: 'in_progress')
    dispatch_agent!(call)
    Voice::CallMessageBuilder.new(call).update_status!(status: call.status)
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
      conversation_id: call.conversation_id,
      provider_call_id: call.provider_call_id,
      livekit_room_name: call.livekit_room_name
    }
  end
end
