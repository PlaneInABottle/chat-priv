# frozen_string_literal: true

class Voice::Recordings::DeleteService
  def self.perform(recording:, storage_config: Voice::Recordings::StorageConfig.new)
    new(recording: recording, storage_config: storage_config).perform
  end

  def initialize(recording:, storage_config:)
    @recording = recording
    @storage_config = storage_config
  end

  def perform
    storage_config.delete_object(recording) if recording.object_key.present?
    recording.destroy!
  end

  private

  attr_reader :recording, :storage_config
end
