require 'rails_helper'

RSpec.describe Voice::Recordings::StorageConfig do
  describe '#configured?' do
    it 'requires voice-specific credentials and does not fall back to global AWS env' do
      result = with_modified_env(
        'VOICE_RECORDING_S3_ACCESS_KEY_ID' => nil,
        'VOICE_RECORDING_S3_SECRET_ACCESS_KEY' => nil,
        'VOICE_RECORDING_S3_BUCKET' => 'recordings',
        'AWS_ACCESS_KEY_ID' => 'global-access',
        'AWS_SECRET_ACCESS_KEY' => 'global-secret'
      ) do
        described_class.new.configured?
      end

      expect(result).to be(false)
    end

    it 'builds object keys under the configured recording prefix' do
      call = create(:call, provider: :livekit, provider_call_id: 'room/with unsafe chars')

      key = with_modified_env('VOICE_RECORDING_S3_PREFIX' => 'tenant-recordings/') do
        described_class.new.object_key_for(call)
      end

      expect(key).to start_with("tenant-recordings/account-#{call.account_id}/call-#{call.id}/")
      expect(key).to end_with('room-with-unsafe-chars.mp4')
    end
  end

  describe '#signed_url' do
    it 'returns nil when voice storage is not configured' do
      recording = create(:voice_recording, status: 'completed')

      result = with_modified_env(
        'VOICE_RECORDING_S3_ACCESS_KEY_ID' => nil,
        'VOICE_RECORDING_S3_SECRET_ACCESS_KEY' => nil,
        'VOICE_RECORDING_S3_BUCKET' => nil
      ) do
        described_class.new.signed_url(recording)
      end

      expect(result).to be_nil
    end
  end
end
