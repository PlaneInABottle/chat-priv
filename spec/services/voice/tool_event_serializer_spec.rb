require 'rails_helper'

RSpec.describe Voice::ToolEventSerializer do
  it 'maps unknown internal tools to a generic public action' do
    created_at = Time.zone.parse('2026-07-14 12:00:00 UTC')
    event = instance_double(
      VoiceToolEvent,
      id: 7,
      tool: 'internal_provider_probe',
      status: 'executed',
      created_at: created_at
    )

    expect(described_class.public_payload(event)).to eq(
      id: 7,
      action: 'generic',
      status: 'executed',
      created_at: created_at.iso8601
    )
  end
end
