# frozen_string_literal: true

class AiDataRetention::PurgeService
  SENSITIVE_VOICE_META_KEYS = %w[
    contact_name
    from_number
    last_voice_agent_payload
    summary
    to_number
  ].freeze
  SENSITIVE_MESSAGE_DATA_KEYS = %w[livekit_room_name recording summary].freeze

  def initialize(account:)
    @account = account
  end

  def perform(kind: nil)
    kinds = kind.present? ? [kind.to_s] : AiDataRetention::Policy::KINDS
    raise ArgumentError, 'Invalid retention kind' unless kinds.all? { |value| AiDataRetention::Policy.valid_kind?(value) }

    kinds.index_with { |value| value == 'text' ? purge_text : purge_voice }
  end

  private

  attr_reader :account

  def purge_text
    cutoff = account.ai_agent_data_retention_days.days.ago
    {
      llm_calls: account.ai_agent_llm_calls.where('created_at < ?', cutoff).delete_all,
      tool_executions: account.ai_agent_tool_executions.where('created_at < ?', cutoff).delete_all,
      test_conversations: AiAgentTestConversation.where(account_id: account.id).where('updated_at < ?', cutoff).delete_all
    }
  end

  def purge_voice
    cutoff = account.voice_ai_data_retention_days.days.ago
    counts = voice_counts

    retained_calls(cutoff).find_each do |call|
      purge_voice_call(call, counts)
    end

    counts
  end

  def retained_calls(cutoff)
    account.calls.where(status: Call::TERMINAL_STATUSES)
           .where('COALESCE(started_at, calls.created_at) < ?', cutoff)
  end

  def voice_counts
    {
      calls: 0,
      transcript_segments: 0,
      tool_events: 0,
      recordings: 0,
      recording_failures: 0,
      attachments: 0
    }
  end

  def purge_voice_call(call, counts)
    counts[:transcript_segments] += call.transcript_segments.delete_all
    counts[:tool_events] += call.voice_tool_events.delete_all
    purge_voice_recordings(call, counts)
    purge_call_attachment(call, counts)
    purge_message_payload(call.message)

    # rubocop:disable Rails/SkipsModelValidations
    call.update_columns(transcript: nil, meta: sanitized_call_meta(call.meta))
    # rubocop:enable Rails/SkipsModelValidations
    counts[:calls] += 1
  end

  def purge_voice_recordings(call, counts)
    call.voice_recordings.find_each do |recording|
      Voice::Recordings::DeleteService.perform(recording: recording)
      counts[:recordings] += 1
    rescue StandardError => e
      counts[:recording_failures] += 1
      Rails.logger.warn("voice recording retention failed recording_id=#{recording.id} error=#{e.class.name}: #{e.message}")
    end
  end

  def purge_call_attachment(call, counts)
    return unless call.recording.attached?

    call.recording.purge
    counts[:attachments] += 1
  rescue StandardError => e
    Rails.logger.warn("voice attachment retention failed call_id=#{call.id} error=#{e.class.name}: #{e.message}")
  end

  def purge_message_payload(message)
    return unless message&.content_attributes.is_a?(Hash)

    attributes = message.content_attributes.deep_dup
    data = attributes['data']
    return unless data.is_a?(Hash)

    data.except!(*SENSITIVE_MESSAGE_DATA_KEYS)
    # rubocop:disable Rails/SkipsModelValidations
    message.update_columns(content_attributes: attributes, updated_at: Time.current)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def sanitized_call_meta(meta)
    return {} unless meta.is_a?(Hash)

    meta.deep_dup.except(*SENSITIVE_VOICE_META_KEYS)
  end
end
