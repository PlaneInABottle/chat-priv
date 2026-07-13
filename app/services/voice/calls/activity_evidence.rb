# frozen_string_literal: true

class Voice::Calls::ActivityEvidence
  ERROR_STATUSES = %w[error rejected].freeze

  def initialize(calls)
    @call_ids = calls.map(&:id)
  end

  def for(call)
    {
      transcript_count: transcript_counts.fetch(call.id, 0),
      action_count: action_counts.fetch(call.id, 0),
      action_error_count: action_error_counts.fetch(call.id, 0),
      recording_status: latest_recordings.fetch(call.id, nil)&.status || 'disabled'
    }
  end

  private

  attr_reader :call_ids

  def transcript_counts
    @transcript_counts ||= CallTranscriptSegment.where(call_id: call_ids).group(:call_id).count
  end

  def action_counts
    @action_counts ||= VoiceToolEvent.where(call_id: call_ids).group(:call_id).count
  end

  def action_error_counts
    @action_error_counts ||= VoiceToolEvent.where(call_id: call_ids, status: ERROR_STATUSES).group(:call_id).count
  end

  def latest_recordings
    @latest_recordings ||= VoiceRecording.where(call_id: call_ids)
                                         .select('DISTINCT ON (call_id) voice_recordings.*')
                                         .order(:call_id, created_at: :desc, id: :desc)
                                         .index_by(&:call_id)
  end
end
