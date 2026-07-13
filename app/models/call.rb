# == Schema Information
#
# Table name: calls
#
#  id                     :bigint           not null, primary key
#  direction              :integer          not null
#  duration_seconds       :integer
#  end_reason             :string
#  meta                   :jsonb
#  provider               :integer          default("twilio"), not null
#  started_at             :datetime
#  status                 :string           default("ringing"), not null
#  transcript             :text
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  accepted_by_agent_id   :bigint
#  account_id             :bigint           not null
#  contact_id             :bigint
#  conversation_id        :bigint
#  inbox_id               :bigint           not null
#  message_id             :bigint
#  provider_call_id       :string           not null
#  voice_agent_release_id :bigint
#
# Indexes
#
#  index_calls_on_account_id_and_contact_id       (account_id,contact_id)
#  index_calls_on_account_id_and_conversation_id  (account_id,conversation_id)
#  index_calls_on_message_id                      (message_id)
#  index_calls_on_provider_and_provider_call_id   (provider,provider_call_id) UNIQUE
#  index_calls_on_voice_agent_release_id          (voice_agent_release_id)
#
# Foreign Keys
#
#  fk_rails_...  (voice_agent_release_id => voice_agent_releases.id) ON DELETE => nullify
#
class Call < ApplicationRecord
  PUBLIC_VOICE_PROVIDER = 'kozmopath_voice'.freeze
  STATUSES = %w[ringing in_progress completed no_answer failed].freeze
  TERMINAL_STATUSES = %w[completed no_answer failed].freeze

  DISPLAY_DIRECTION = { 'incoming' => 'inbound', 'outgoing' => 'outbound' }.freeze
  DEFAULT_STUN_URL = 'stun:stun.l.google.com:19302'.freeze

  store_accessor :meta, :conference_sid, :twilio_conference_sid, :recording_sid, :parent_call_sid,
                 :initiated_at, :ended_at, :livekit_room_name, :handoff_status, :ai_status, :summary,
                 :test_call_source, :test_call_initiated_by_user_id

  enum :provider, { twilio: 0, whatsapp: 1, livekit: 2 }
  enum :direction, { incoming: 0, outgoing: 1 }

  belongs_to :account
  belongs_to :inbox
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true
  belongs_to :message, optional: true, inverse_of: :call
  belongs_to :accepted_by_agent, class_name: 'User', optional: true
  belongs_to :voice_agent_release, optional: true

  has_many :transcript_segments, class_name: 'CallTranscriptSegment', dependent: :destroy
  has_many :voice_tool_events, dependent: :destroy
  has_many :voice_recordings, dependent: :destroy
  has_one_attached :recording

  validates :provider_call_id, presence: true
  validates :provider, presence: true
  validates :direction, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :conversation, :contact, presence: true, unless: :test_call?

  scope :active, -> { where.not(status: TERMINAL_STATUSES) }
  scope :by_conference_sid, ->(sid) { where("meta->>'conference_sid' = ?", sid) }
  scope :by_twilio_conference_sid, ->(sid) { where("meta->>'twilio_conference_sid' = ?", sid) }

  def self.find_by_provider_call_id(provider, sid)
    find_by(provider: provider, provider_call_id: sid)
  end

  def self.default_ice_servers
    urls = ENV.fetch('VOICE_CALL_STUN_URLS', DEFAULT_STUN_URL).split(',').filter_map { |u| u.strip.presence }
    [{ urls: urls }]
  end

  def default_conference_sid
    "conf_account_#{account_id}_call_#{id}"
  end

  def direction_label
    DISPLAY_DIRECTION[direction]
  end

  def terminal?
    TERMINAL_STATUSES.include?(status)
  end

  def test_call?
    ActiveModel::Type::Boolean.new.cast(meta&.fetch('test_call', false))
  end

  def display_status
    status.to_s.tr('_', '-')
  end

  def from_number
    return meta['from_number'] if livekit?

    incoming? ? contact&.phone_number : inbox_channel_phone_number
  end

  def to_number
    return meta['to_number'] if livekit?

    incoming? ? inbox_channel_phone_number : contact&.phone_number
  end

  def recording_url
    if livekit?
      latest_recording = VoiceRecording.where(call_id: id).completed.latest_first.first
      return Voice::Recordings::StorageConfig.new.signed_url(latest_recording) if latest_recording
    end

    return nil unless recording.attached?

    Rails.application.routes.url_helpers.rails_blob_url(recording)
  end

  def push_event_data
    event_payload.merge(number_payload).merge(voice_payload)
  end

  def public_provider
    livekit? ? PUBLIC_VOICE_PROVIDER : provider
  end

  def public_content_attributes(attributes)
    return attributes unless livekit? && attributes.is_a?(Hash)

    sanitized = attributes.deep_dup
    data = sanitized['data'] || sanitized[:data]
    return sanitized unless data.is_a?(Hash)

    call_reference = data.delete('call_sid') || data.delete(:call_sid) || provider_call_id
    room_name = data.delete('livekit_room_name') || data.delete(:livekit_room_name) || livekit_room_name
    data['call_reference'] = call_reference
    data['call_source'] = public_provider
    data['room_name'] = room_name if room_name.present?
    sanitized
  end

  private

  def inbox_channel_phone_number
    return unless inbox.channel.respond_to?(:phone_number)

    inbox.channel.phone_number
  end

  def event_payload
    payload = {
      id: id,
      direction: direction,
      status: display_status,
      duration_seconds: duration_seconds,
      end_reason: end_reason,
      conference_sid: conference_sid,
      accepted_by_agent_id: accepted_by_agent_id,
      accepted_by_agent_name: accepted_by_agent&.available_name,
      started_at: started_at&.to_i,
      ended_at: ended_at
    }

    return payload.merge(call_reference: provider_call_id, provider: public_provider) if livekit?

    payload.merge(provider_call_id: provider_call_id, provider: provider)
  end

  def number_payload
    {
      from_number: from_number,
      to_number: to_number
    }
  end

  def voice_payload
    payload = {
      voice_number_id: meta&.fetch('voice_number_id', nil),
      voice_provider_connection_id: meta&.fetch('voice_provider_connection_id', nil),
      test_call: test_call?,
      test_call_source: test_call_source,
      test_call_initiated_by_user_id: test_call_initiated_by_user_id,
      handoff_status: handoff_status,
      ai_status: ai_status,
      recording_url: recording_url,
      transcript: transcript
    }

    payload[:room_name] = livekit_room_name if livekit?
    payload
  end
end
