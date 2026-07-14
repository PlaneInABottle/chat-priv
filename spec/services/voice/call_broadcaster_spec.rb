require 'rails_helper'

RSpec.describe Voice::CallBroadcaster do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_api, account: account).inbox }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: inbox,
      provider: :livekit,
      provider_call_id: 'room-public-tool-event',
      meta: { 'test_call' => true }
    )
  end
  let(:event) do
    call.voice_tool_events.create!(
      account: account,
      tool: 'ikas_catalog_search',
      status: 'executed',
      arguments: { query: 'private catalog query' },
      result: { internal_note: 'private result' },
      error_message: 'private error',
      duration_ms: 42,
      source: 'livekit_agent'
    )
  end

  before do
    allow(ActionCable.server).to receive(:broadcast)
  end

  it 'broadcasts only the public tool event summary' do
    described_class.tool_event(call, event)

    expect(ActionCable.server).to have_received(:broadcast).with(
      "account_#{account.id}",
      {
        event: 'voice_call.tool_event',
        data: {
          call_id: call.id,
          account_id: account.id,
          event: {
            id: event.id,
            action: 'catalog_search',
            status: 'executed',
            created_at: event.created_at.iso8601
          }
        }
      }
    )
  end
end
