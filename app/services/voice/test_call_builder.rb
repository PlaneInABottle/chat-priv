class Voice::TestCallBuilder
  def self.perform!(account:, inbox:, caller_name: nil, caller_number: nil, initiated_by: nil)
    new(account: account, inbox: inbox, caller_name: caller_name, caller_number: caller_number, initiated_by: initiated_by).perform!
  end

  def initialize(account:, inbox:, caller_name: nil, caller_number: nil, initiated_by: nil)
    @account = account
    @inbox = inbox
    @caller_name = caller_name.presence || 'Test caller'
    @caller_number = caller_number.presence || '+900000000000'
    @initiated_by = initiated_by
  end

  def perform!
    raise ArgumentError, 'Voice MVP test calls require an API inbox' unless inbox.api?

    setting = ensure_setting!
    raise ArgumentError, 'Voice agent must be enabled before starting a test call' unless setting.voice_agent&.enabled?

    room_name = room_name_for(setting)
    call = build_call!(setting, room_name)
    start_call!(call, room_name)
    call
  end

  private

  attr_reader :account, :inbox, :caller_name, :caller_number, :initiated_by

  def ensure_setting!
    setting = account.voice_inbox_settings.find_or_create_by!(inbox: inbox) do |new_setting|
      new_setting.status = 'test_only'
      new_setting.voice_agent = default_voice_agent
    end
    return setting if setting.voice_agent_id.present?

    setting.update!(voice_agent: default_voice_agent)
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
      'test_call' => true,
      'test_call_source' => 'voice_ai_settings',
      'test_call_initiated_by_user_id' => initiated_by&.id,
      'handoff_status' => 'none',
      'ai_status' => 'waiting'
    }.compact
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
      conversation_id: nil,
      provider_call_id: call.provider_call_id,
      livekit_room_name: call.livekit_room_name,
      voice_agent_id: call.meta['voice_agent_id']
    }.compact
  end

  def default_voice_agent
    @default_voice_agent ||= account.voice_agents.order(:created_at).first || account.create_default_voice_agent!
  end
end
