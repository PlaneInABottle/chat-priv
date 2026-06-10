class Voice::TranscriptAppender
  DEFAULT_ATTRIBUTES = {
    source: 'livekit_agent',
    confidence: nil,
    started_at: nil,
    ended_at: nil,
    external_segment_id: nil,
    metadata: {}
  }.freeze

  def self.perform!(call:, **attributes)
    new(call: call, attributes: attributes).perform!
  end

  def initialize(call:, attributes:)
    @call = call
    @attributes = DEFAULT_ATTRIBUTES.merge(attributes.symbolize_keys)
    @attributes[:metadata] ||= {}
  end

  def perform!
    return existing_segment if existing_segment

    segment = call.transcript_segments.create!(segment_attributes)
    append_transcript_line!(segment)
    broadcast_transcript_segment(call, segment)
    segment
  end

  private

  attr_reader :call, :attributes

  def segment_attributes
    attributes.slice(:role, :text, :source, :confidence, :started_at, :ended_at, :external_segment_id, :metadata).merge(
      account: call.account,
      conversation: call.conversation
    )
  end

  def existing_segment
    return if external_segment_id.blank?

    @existing_segment ||= call.transcript_segments.find_by(external_segment_id: external_segment_id)
  end

  def broadcast_transcript_segment(call, segment)
    Voice::CallBroadcaster.transcript_segment(call, segment)
  rescue StandardError => e
    Rails.logger.warn("voice broadcast failed event=transcript_segment call_id=#{call.id} error=#{e.message}")
  end

  def append_transcript_line!(segment)
    new_line = "#{segment.role}: #{segment.text}"
    call.transcript = [call.transcript.presence, new_line].compact.join("\n")
    call.update_column(:transcript, call.transcript)
  end

  def external_segment_id
    attributes[:external_segment_id]
  end
end
