require 'rails_helper'

RSpec.describe Voice::Recordings::DeleteService do
  it 'deletes the external object before destroying its database record' do
    recording = instance_double(VoiceRecording, object_key: 'voice/call.mp4')
    storage_config = instance_double(Voice::Recordings::StorageConfig)
    expect(storage_config).to receive(:delete_object).with(recording).ordered
    expect(recording).to receive(:destroy!).ordered

    described_class.perform(recording: recording, storage_config: storage_config)
  end
end
