require 'open3'

class Voice::Telephony::LocalAsteriskHangupService
  COMPOSE_FILE = Rails.root.join('dev/voice_sip/docker-compose.yml').to_s
  ASTERISK_SERVICE = 'asterisk'.freeze
  LIVEKIT_ENDPOINT = 'livekit'.freeze

  def self.perform(call:)
    new(call: call).perform
  end

  def initialize(call:)
    @call = call
  end

  def perform
    return skipped_result('not_local_asterisk_harness') unless local_asterisk_harness?

    channels = active_target_channels
    return { 'status' => 'not_found', 'channels' => [] } if channels.blank?

    output = run_asterisk("channel request hangup #{channels.join(' ')}")
    {
      'status' => 'requested',
      'channels' => channels,
      'output' => output.to_s.truncate(500)
    }
  rescue StandardError => e
    {
      'status' => 'failed',
      'error' => e.message.to_s.truncate(500),
      'error_class' => e.class.name
    }
  end

  private

  attr_reader :call

  def active_target_channels
    run_asterisk('core show channels concise')
      .lines
      .filter_map { |line| line.split('!', 2).first.presence }
      .select { |channel| target_channel?(channel) }
  end

  def target_channel?(channel)
    endpoint_names.any? { |endpoint| channel.start_with?("PJSIP/#{endpoint}-") }
  end

  def endpoint_names
    [softphone_user, LIVEKIT_ENDPOINT].compact_blank.uniq
  end

  def softphone_user
    voice_number&.settings&.fetch('softphone_user', nil).presence || ENV['ASTERISK_SOFTPHONE_USER'].presence
  end

  def local_asterisk_harness?
    development_runtime? &&
      call.livekit? &&
      compose_file_present? &&
      test_sip_connection? &&
      local_asterisk_connection?
  end

  def development_runtime?
    Rails.env.development?
  end

  def compose_file_present?
    File.exist?(COMPOSE_FILE)
  end

  def test_sip_connection?
    provider_connection&.provider == 'test_sip'
  end

  def local_asterisk_connection?
    provider_connection&.settings&.fetch('kind', nil) == 'local_asterisk'
  end

  def provider_connection
    @provider_connection ||= VoiceProviderConnection.find_by(id: call.meta&.fetch('voice_provider_connection_id', nil))
  end

  def voice_number
    @voice_number ||= VoiceNumber.find_by(id: call.meta&.fetch('voice_number_id', nil))
  end

  def run_asterisk(command)
    output, error, status = Open3.capture3(
      'docker',
      'compose',
      '-f',
      COMPOSE_FILE,
      'exec',
      '-T',
      ASTERISK_SERVICE,
      'asterisk',
      '-rx',
      command
    )
    raise "Asterisk command failed: #{error.presence || output}" unless status.success?

    output
  end

  def skipped_result(reason)
    {
      'status' => 'skipped',
      'reason' => reason
    }
  end
end
