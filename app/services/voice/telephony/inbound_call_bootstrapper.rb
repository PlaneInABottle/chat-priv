class Voice::Telephony::InboundCallBootstrapper
  def self.perform!(provider_call_id:, metadata: {})
    new(provider_call_id: provider_call_id, metadata: metadata).perform!
  end

  def initialize(provider_call_id:, metadata: {})
    @provider_call_id = provider_call_id.to_s
    @metadata = metadata.to_h.with_indifferent_access
  end

  def perform!
    existing_call || build_call!
  end

  private

  attr_reader :provider_call_id, :metadata

  def existing_call
    @existing_call ||= Call.where(provider: :livekit).find_by(provider_call_id: provider_call_id) ||
                       Call.where(provider: :livekit).where("meta->>'livekit_room_name' = ?", provider_call_id).first
  end

  def build_call!
    resolved_setting = voice_inbox_setting
    raise ActiveRecord::RecordNotFound, 'Voice number or voice inbox setting not configured' unless resolved_setting&.voice_agent_id
    raise ActiveRecord::RecordNotFound, 'Voice assistant is paused' unless resolved_setting.voice_agent&.enabled?

    call = Voice::InboundCallBuilder.perform!(
      inbox: resolved_setting.inbox,
      from_number: from_number,
      call_sid: provider_call_id,
      provider: :livekit,
      extra_meta: inbound_meta(resolved_setting)
    )
    activate_call!(call)
  end

  def activate_call!(call)
    return call if call.terminal?

    call.update!(
      status: 'in_progress',
      started_at: call.started_at || Time.zone.now,
      meta: call.meta.merge('livekit_room_name' => provider_call_id)
    )
    Voice::CallMessageBuilder.new(call).update_status!(status: call.status) if call.message_id
    start_recording!(call)
    Voice::CallBroadcaster.safe_call_status_changed(call)
    call
  end

  def start_recording!(call)
    Voice::Recordings::StartService.perform(call: call)
  rescue StandardError => e
    Rails.logger.warn("voice recording start failed call_id=#{call.id} error=#{e.class.name}: #{e.message}")
  end

  def inbound_meta(setting)
    sip_metadata.merge(
      'livekit_room_name' => provider_call_id,
      'voice_inbox_setting_id' => setting.id,
      'voice_agent_id' => setting.voice_agent_id,
      'voice_number_id' => voice_number&.id,
      'voice_provider_connection_id' => voice_number&.voice_provider_connection_id,
      'to_number' => to_number,
      'handoff_status' => 'none',
      'ai_status' => 'waiting'
    ).compact
  end

  def sip_metadata
    metadata.slice(
      :contact_name,
      :sip_call_id,
      :sip_trunk_id,
      :sip_rule_id,
      :sip_phone_number,
      :sip_trunk_phone_number,
      :livekit_inbound_trunk_id,
      :livekit_dispatch_rule_id
    ).stringify_keys
  end

  def voice_inbox_setting
    @voice_inbox_setting ||= voice_number&.voice_inbox_setting || explicit_voice_inbox_setting
  end

  def voice_number
    @voice_number ||= find_voice_number
  end

  def find_voice_number
    number = voice_number_scope.find_by(id: metadata[:voice_number_id]) if metadata[:voice_number_id].present?
    return number if number

    number = find_voice_number_by_phone
    return number if number

    find_voice_number_by_livekit_ids
  end

  def find_voice_number_by_phone
    normalized = VoiceNumber.normalize_number(to_number)
    return if normalized.blank?

    scope = voice_number_scope.where(phone_number: normalized)
    scope.active.first || scope.first
  end

  def find_voice_number_by_livekit_ids
    return if metadata[:livekit_inbound_trunk_id].blank? && metadata[:livekit_dispatch_rule_id].blank?

    scope = voice_number_scope
    scope = scope.where(livekit_inbound_trunk_id: metadata[:livekit_inbound_trunk_id]) if metadata[:livekit_inbound_trunk_id].present?
    scope = scope.where(livekit_dispatch_rule_id: metadata[:livekit_dispatch_rule_id]) if metadata[:livekit_dispatch_rule_id].present?
    scope.active.first || scope.first
  end

  def voice_number_scope
    return VoiceNumber.none if scoped_account.blank?

    scoped_account.voice_numbers
  end

  def scoped_account
    @scoped_account ||= Account.find_by(id: metadata[:account_id]) if metadata[:account_id].present?
  end

  def explicit_voice_inbox_setting
    return unless explicit_voice_inbox_setting_resolvable?

    setting = scoped_account&.voice_inbox_settings&.find_by(id: metadata[:voice_inbox_setting_id])
    return setting if setting && inbox_matches?(setting)

    nil
  end

  def explicit_voice_inbox_setting_resolvable?
    metadata[:voice_inbox_setting_id].present? && metadata[:account_id].present?
  end

  def inbox_matches?(setting)
    metadata[:inbox_id].blank? || setting.inbox_id.to_s == metadata[:inbox_id].to_s
  end

  def from_number
    metadata[:from_number].presence ||
      metadata[:sip_phone_number].presence ||
      metadata[:caller_number].presence ||
      phone_number_from_room_name.presence ||
      "sip:#{provider_call_id}"
  end

  def to_number
    metadata[:to_number].presence ||
      metadata[:sip_trunk_phone_number].presence ||
      metadata[:phone_number].presence ||
      metadata[:called_number].presence
  end

  def phone_number_from_room_name
    provider_call_id.match(/(?:^|[_-])(\+?[1-9]\d{6,14})(?:[_-]|$)/)&.[](1)
  end
end
