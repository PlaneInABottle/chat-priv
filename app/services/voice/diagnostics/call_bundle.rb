require 'net/http'

# rubocop:disable Metrics/ClassLength
class Voice::Diagnostics::CallBundle
  VOICE_AGENT_HEALTH_TIMEOUT = 1
  CALLER_END_REASONS = %w[
    caller_disconnected caller_rejected caller_unavailable sip_trunk_failure participant_timeout
  ].freeze
  AGENT_END_REASONS = %w[
    agent_ended agent_ended_from_popup agent_ended_from_session browser_test_ended conversation_resolved voice_ai_disabled
  ].freeze

  def initialize(call:, raw: false, include_livekit: true, include_system_health: true)
    @call = call
    @raw = raw
    @include_livekit = include_livekit
    @include_system_health = include_system_health
  end

  def payload
    base_payload.merge(context_payload).merge(evidence_payload).compact
  end

  def base_payload
    {
      schema_version: 1,
      generated_at: Time.zone.now.iso8601(3),
      redaction: redaction_payload,
      summary: summary,
      failure_reasons: failure_reasons,
      next_checks: next_checks
    }
  end

  def context_payload
    {
      call: call_payload,
      account: account_payload,
      conversation: conversation_payload,
      livekit: livekit_payload,
      sip: sip_payload,
      voice_agent: voice_agent_payload,
      usage: usage_payload
    }
  end

  def evidence_payload
    {
      timeline: timeline,
      transcript_segments: transcript_segments_payload,
      tool_events: tool_events_payload,
      recordings: recordings_payload,
      system_health: system_health_payload
    }
  end

  private

  attr_reader :call, :raw, :include_livekit, :include_system_health

  def redaction_payload
    {
      mode: raw ? 'raw' : 'redacted',
      raw_available_to_super_admin: true
    }
  end

  def summary
    [
      call.test_call? ? 'Test Voice AI call' : 'Live Voice AI call',
      "status=#{call.status}",
      "ai_status=#{call.ai_status.presence || 'unknown'}",
      "end_reason=#{call.end_reason.presence || 'none'}"
    ].join(' · ')
  end

  def call_payload
    redact(call_identity_payload.merge(call_state_payload).merge(call_number_payload).merge(meta: call.meta || {}))
  end

  def call_identity_payload
    {
      id: call.id,
      provider: call.provider,
      provider_call_id: call.provider_call_id,
      direction: call.direction,
      account_id: call.account_id,
      inbox_id: call.inbox_id,
      contact_id: call.contact_id,
      conversation_id: call.conversation_id,
      conversation_display_id: call.conversation&.display_id,
      message_id: call.message_id
    }
  end

  def call_state_payload
    {
      status: call.status,
      display_status: call.display_status,
      test_call: call.test_call?,
      test_call_source: call.test_call_source,
      started_at: call.started_at&.iso8601,
      ended_at: call.ended_at,
      duration_seconds: call.duration_seconds,
      end_reason: call.end_reason,
      handoff_status: call.handoff_status,
      ai_status: call.ai_status
    }
  end

  def call_number_payload
    {
      from_number: call.from_number,
      to_number: call.to_number
    }
  end

  def account_payload
    {
      id: call.account_id,
      name: call.account&.name,
      voice_ai_enabled: call.account&.voice_ai_enabled?,
      ai_agent_enabled: call.account&.ai_agent_enabled?
    }
  end

  def conversation_payload
    conversation = call.conversation
    return unless conversation

    {
      id: conversation.id,
      display_id: conversation.display_id,
      status: conversation.status,
      assignee_id: conversation.assignee_id,
      team_id: conversation.team_id,
      url: "/app/accounts/#{call.account_id}/conversations/#{conversation.display_id}"
    }
  end

  def livekit_payload
    room_summary = include_livekit ? Voice::Livekit::RoomService.participant_summary(call: call) : nil
    redact(
      {
        room_name: call.livekit_room_name.presence || call.provider_call_id,
        provider_call_id: call.provider_call_id,
        room_summary: room_summary,
        dispatch: call.meta&.fetch('voice_agent_dispatch', nil),
        customer_removal: call.meta&.fetch('livekit_customer_removal', nil),
        room_delete: call.meta&.fetch('livekit_room_delete', nil),
        stale_check: call.meta&.fetch('livekit_stale_check', nil)
      }.compact
    )
  end

  def sip_payload
    meta = call.meta || {}
    keys = %w[
      voice_number_id voice_provider_connection_id voice_inbox_setting_id livekit_inbound_trunk_id livekit_dispatch_rule_id
      sip_call_id sip_trunk_id sip_rule_id sip_phone_number sip_trunk_phone_number from_number to_number caller_number called_number
    ]
    redact(keys.index_with { |key| meta[key] }.compact)
  end

  def voice_agent_payload
    return unless voice_agent

    {
      id: voice_agent.id,
      name: voice_agent.name,
      enabled: voice_agent.enabled?,
      architecture: voice_agent.architecture,
      provider: voice_agent.provider,
      model: voice_agent.model,
      voice: voice_agent.voice,
      language: voice_agent.language,
      enabled_tool_keys: VoiceAgents::Config.new(voice_agent.tools_config).enabled_tool_keys
    }
  end

  def usage_payload
    {
      text_ai: AiAgents::Usage::Summary.new(account: call.account).payload,
      voice_ai: Voice::Usage::Summary.new(account: call.account).payload
    }
  end

  def timeline
    [
      call_timeline_events,
      transcript_timeline_events,
      tool_timeline_events,
      recording_timeline_events
    ].flatten.sort_by { |event| event[:at].to_s }
  end

  def call_timeline_events
    [
      timeline_event(call.created_at, 'call_created', { status: call.status }),
      (timeline_event(call.started_at, 'call_started', {}) if call.started_at),
      (timeline_event(call.created_at, 'voice_agent_event', last_voice_agent_payload) if last_voice_agent_event?),
      (timeline_event(call.updated_at, 'call_ended', { status: call.status, end_reason: call.end_reason }) if call.terminal?)
    ].compact
  end

  def transcript_timeline_events
    transcript_segments.map { |segment| timeline_event(segment.created_at, "transcript_#{segment.role}", { id: segment.id }) }
  end

  def tool_timeline_events
    tool_events.map { |event| timeline_event(event.created_at, "tool_#{event.status}", { id: event.id, tool: event.tool }) }
  end

  def recording_timeline_events
    recordings.map { |recording| timeline_event(recording.created_at, "recording_#{recording.status}", { id: recording.id }) }
  end

  def timeline_event(time, type, data)
    {
      at: time&.iso8601,
      type: type,
      data: redact(data)
    }.compact
  end

  def transcript_segments_payload
    transcript_segments.map do |segment|
      redact(
        {
          id: segment.id,
          role: segment.role,
          source: segment.source,
          text: segment.text,
          confidence: segment.confidence,
          started_at: segment.started_at&.iso8601,
          ended_at: segment.ended_at&.iso8601,
          created_at: segment.created_at.iso8601
        }
      )
    end
  end

  def tool_events_payload
    tool_events.map do |event|
      redact(
        {
          id: event.id,
          tool: event.tool,
          status: event.status,
          arguments: event.arguments,
          result: event.result,
          error_message: event.error_message,
          duration_ms: event.duration_ms,
          source: event.source,
          external_id: event.external_id,
          created_at: event.created_at.iso8601
        }
      )
    end
  end

  def recordings_payload
    recordings.map do |recording|
      redact(
        {
          id: recording.id,
          status: recording.status,
          storage_provider: recording.storage_provider,
          bucket: recording.bucket,
          object_key: recording.object_key,
          content_type: recording.content_type,
          duration_seconds: recording.duration_seconds,
          egress_id: recording.egress_id,
          error_message: recording.error_message,
          started_at: recording.started_at&.iso8601,
          completed_at: recording.completed_at&.iso8601,
          metadata: recording.metadata || {}
        }
      )
    end
  end

  def system_health_payload
    return unless include_system_health

    {
      rails: { status: 'ok' },
      sidekiq: sidekiq_health,
      voice_agent: voice_agent_health,
      livekit: {
        status: livekit_configured? ? 'configured' : 'skipped',
        reason: livekit_configured? ? nil : 'livekit_not_configured'
      }.compact
    }
  end

  def sidekiq_health
    {
      status: sidekiq_process_count.positive? ? 'ok' : 'degraded',
      process_count: sidekiq_process_count,
      queue_count: sidekiq_queue_count
    }
  rescue StandardError => e
    { status: 'error', error: e.message.to_s.truncate(500), error_class: e.class.name }
  end

  def sidekiq_process_count
    @sidekiq_process_count ||= Sidekiq::ProcessSet.new.size
  end

  def sidekiq_queue_count
    @sidekiq_queue_count ||= Sidekiq::Queue.all.sum(&:size)
  end

  def voice_agent_health
    uri = voice_agent_health_uri
    return { status: 'skipped', reason: 'voice_agent_health_url_not_configured' } unless uri

    response = Net::HTTP.start(
      uri.host,
      uri.port,
      use_ssl: uri.scheme == 'https',
      open_timeout: VOICE_AGENT_HEALTH_TIMEOUT,
      read_timeout: VOICE_AGENT_HEALTH_TIMEOUT
    ) do |http|
      http.get(uri.request_uri)
    end
    payload = JSON.parse(response.body.presence || '{}')
    { status: response.is_a?(Net::HTTPSuccess) ? 'ok' : 'degraded', http_status: response.code.to_i, payload: payload }
  rescue StandardError => e
    { status: 'error', error: e.message.to_s.truncate(500), error_class: e.class.name }
  end

  def voice_agent_health_uri
    url = ENV['VOICE_AGENT_HEALTH_URL'].presence
    url ||= "http://127.0.0.1:#{ENV['VOICE_AGENT_HEALTH_PORT']}/health" if ENV['VOICE_AGENT_HEALTH_PORT'].present?
    URI(url) if url.present?
  rescue URI::InvalidURIError
    nil
  end

  def livekit_configured?
    Voice::Livekit::TwirpClient.new(
      room_name: call.livekit_room_name.presence || call.provider_call_id,
      subject: 'voice-diagnostics'
    ).configured?
  end

  def failure_reasons
    failure_reason_checks.filter_map { |reason, present| reason if present }.uniq
  end

  def failure_reason_checks
    {
      'recording_failed' => recording_failed?,
      'tool_failed' => tool_failed?,
      'agent_never_joined' => agent_never_joined?,
      'call_ended_by_caller' => CALLER_END_REASONS.include?(call.end_reason),
      'call_ended_by_agent' => AGENT_END_REASONS.include?(call.end_reason),
      'livekit_room_delete_failed' => call.meta&.dig('livekit_room_delete', 'status') == 'failed',
      'livekit_customer_removal_failed' => call.meta&.dig('livekit_customer_removal', 'status') == 'failed'
    }
  end

  def recording_failed?
    recordings.any? { |recording| recording.status == 'failed' } || call.meta&.dig('recording_stop', 'status') == 'failed'
  end

  def tool_failed?
    tool_events.any? { |event| event.status.in?(%w[error rejected]) }
  end

  def agent_never_joined?
    return false if call.ai_status.in?(%w[active completed handoff_requested silent])
    return false if call.meta&.fetch('last_voice_agent_event', nil).present?

    call.terminal? || call.created_at < 2.minutes.ago
  end

  def next_checks
    checks = []
    checks << 'Inspect voice agent worker health and LiveKit dispatch logs.' if failure_reasons.include?('agent_never_joined')
    checks << 'Inspect recording egress webhook and storage credentials.' if failure_reasons.include?('recording_failed')
    checks << 'Inspect failed tool event arguments, result, and integration connection status.' if failure_reasons.include?('tool_failed')
    checks << 'Inspect LiveKit room participant removal/delete result.' if failure_reasons.any? { |reason| reason.start_with?('livekit_') }
    checks << 'No obvious failure detected from persisted call diagnostics.' if checks.empty?
    checks
  end

  def last_voice_agent_payload
    {
      event: call.meta&.fetch('last_voice_agent_event', nil),
      payload: call.meta&.fetch('last_voice_agent_payload', nil)
    }.compact
  end

  def last_voice_agent_event?
    call.meta&.fetch('last_voice_agent_event', nil).present?
  end

  def transcript_segments
    @transcript_segments ||= CallTranscriptSegment.where(call_id: call.id).order(:created_at, :id)
  end

  def tool_events
    @tool_events ||= VoiceToolEvent.where(call_id: call.id).order(:created_at, :id)
  end

  def recordings
    @recordings ||= VoiceRecording.where(call_id: call.id).latest_first
  end

  def voice_agent
    return @voice_agent if defined?(@voice_agent)

    voice_agent_id = call.meta&.fetch('voice_agent_id', nil)
    @voice_agent = voice_agent_id.present? ? call.account.voice_agents.find_by(id: voice_agent_id) : nil
  end

  def redact(value)
    return value if raw

    case value
    when Hash
      value.transform_values { |item| redact(item) }
    when Array
      value.map { |item| redact(item) }
    when String
      AiAgents::PrivacyRedactor.redact_text(value)
    else
      value
    end
  end
end
# rubocop:enable Metrics/ClassLength
