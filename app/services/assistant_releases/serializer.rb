# frozen_string_literal: true

class AssistantReleases::Serializer
  def initialize(release, include_snapshot: false)
    @release = release
    @include_snapshot = include_snapshot
  end

  def payload
    {
      id: release.id,
      revision: release.revision,
      source: release.source,
      fingerprint: release.fingerprint,
      created_at: release.created_at.iso8601,
      created_by: created_by_payload,
      snapshot: include_snapshot ? release.snapshot : nil
    }.compact
  end

  private

  attr_reader :release, :include_snapshot

  def created_by_payload
    return unless release.created_by

    { id: release.created_by.id, name: release.created_by.available_name }
  end
end
