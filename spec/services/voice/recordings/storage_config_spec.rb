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

    it 'uses a short-lived signed URL for completed recording playback' do
      recording = create(
        :voice_recording,
        status: 'completed',
        bucket: 'recordings',
        object_key: 'voice-recordings/account-1/call-1/room.mp4',
        content_type: 'audio/mp4'
      )
      presigner = instance_double(Aws::S3::Presigner)
      allow(Aws::S3::Presigner).to receive(:new).and_return(presigner)
      allow(presigner).to receive(:presigned_url).and_return('https://recordings.example/signed-url')

      result = with_modified_env(
        'VOICE_RECORDING_S3_ACCESS_KEY_ID' => 'recording-access',
        'VOICE_RECORDING_S3_SECRET_ACCESS_KEY' => 'recording-secret',
        'VOICE_RECORDING_S3_BUCKET' => 'recordings',
        'VOICE_RECORDING_S3_ENDPOINT' => 'https://recordings.example'
      ) do
        described_class.new.signed_url(recording)
      end

      expect(result).to eq('https://recordings.example/signed-url')
      expect(presigner).to have_received(:presigned_url).with(
        :get_object,
        hash_including(
          bucket: 'recordings',
          key: 'voice-recordings/account-1/call-1/room.mp4',
          expires_in: described_class::SIGNED_URL_EXPIRES_IN,
          response_content_type: 'audio/mp4'
        )
      )
    end
  end

  describe '#delete_object' do
    it 'deletes the recording from its persisted bucket' do
      recording = instance_double(
        VoiceRecording,
        bucket: 'call-recordings',
        object_key: 'voice-recordings/account-1/call-1/room.mp4'
      )
      s3_client = instance_double(Aws::S3::Client)
      allow(Aws::S3::Client).to receive(:new).and_return(s3_client)
      expect(s3_client).to receive(:delete_object).with(
        bucket: 'call-recordings',
        key: 'voice-recordings/account-1/call-1/room.mp4'
      )

      with_modified_env(
        'VOICE_RECORDING_S3_ACCESS_KEY_ID' => 'recording-access',
        'VOICE_RECORDING_S3_SECRET_ACCESS_KEY' => 'recording-secret',
        'VOICE_RECORDING_S3_BUCKET' => 'default-recordings'
      ) do
        described_class.new.delete_object(recording)
      end
    end
  end
end
