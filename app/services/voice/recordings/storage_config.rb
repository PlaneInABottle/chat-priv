require 'aws-sdk-s3'

class Voice::Recordings::StorageConfig
  DEFAULT_PROVIDER = 's3_compatible'.freeze
  DEFAULT_OBJECT_KEY_PREFIX = 'voice-recordings'.freeze
  DEFAULT_REGION = 'auto'.freeze
  DEFAULT_CONTENT_TYPE = 'audio/mp4'.freeze
  SIGNED_URL_EXPIRES_IN = 15.minutes.to_i

  def provider
    ENV.fetch('VOICE_RECORDING_STORAGE_PROVIDER', DEFAULT_PROVIDER)
  end

  def configured?
    provider == DEFAULT_PROVIDER &&
      access_key_id.present? &&
      secret_access_key.present? &&
      bucket.present? &&
      object_key_prefix.present?
  end

  def bucket
    ENV['VOICE_RECORDING_S3_BUCKET'].presence
  end

  def content_type
    ENV.fetch('VOICE_RECORDING_CONTENT_TYPE', DEFAULT_CONTENT_TYPE)
  end

  def content_type_for(object_key)
    case File.extname(object_key.to_s).downcase
    when '.ogg', '.oga'
      'audio/ogg'
    when '.mp3'
      'audio/mpeg'
    when '.wav'
      'audio/wav'
    when '.m4a'
      'audio/mp4'
    else
      content_type
    end
  end

  def object_key_for(call)
    [
      object_key_prefix,
      "account-#{call.account_id}",
      "call-#{call.id}",
      "#{call.provider_call_id.parameterize.presence || SecureRandom.hex(8)}.mp4"
    ].join('/')
  end

  def s3_upload
    {
      access_key: access_key_id,
      secret: secret_access_key,
      bucket: bucket,
      region: region,
      endpoint: endpoint,
      force_path_style: force_path_style?
    }.compact
  end

  def object_key_prefix
    ENV.fetch('VOICE_RECORDING_S3_PREFIX', DEFAULT_OBJECT_KEY_PREFIX).to_s.delete_prefix('/').delete_suffix('/').presence
  end

  def signed_url(recording, expires_in: SIGNED_URL_EXPIRES_IN)
    return if recording.object_key.blank?
    return unless configured?

    presigner.presigned_url(
      :get_object,
      bucket: recording.bucket.presence || bucket,
      key: recording.object_key,
      expires_in: expires_in,
      response_content_type: recording.content_type.presence || content_type
    )
  end

  def delete_object(recording)
    return if recording.object_key.blank?
    raise 'Voice recording storage is not configured' unless configured?

    s3_client.delete_object(
      bucket: recording.bucket.presence || bucket,
      key: recording.object_key
    )
  end

  private

  def presigner
    Aws::S3::Presigner.new(client: s3_client)
  end

  def s3_client
    Aws::S3::Client.new(
      access_key_id: access_key_id,
      secret_access_key: secret_access_key,
      region: region,
      endpoint: endpoint,
      force_path_style: force_path_style?
    )
  end

  def access_key_id
    ENV['VOICE_RECORDING_S3_ACCESS_KEY_ID'].presence
  end

  def secret_access_key
    ENV['VOICE_RECORDING_S3_SECRET_ACCESS_KEY'].presence
  end

  def region
    ENV.fetch('VOICE_RECORDING_S3_REGION', DEFAULT_REGION)
  end

  def endpoint
    ENV['VOICE_RECORDING_S3_ENDPOINT'].presence
  end

  def force_path_style?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('VOICE_RECORDING_S3_FORCE_PATH_STYLE', false))
  end
end
