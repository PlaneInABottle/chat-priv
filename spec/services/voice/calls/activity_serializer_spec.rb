require 'rails_helper'

RSpec.describe Voice::Calls::ActivitySerializer do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:voice_agent) { create(:voice_agent, account: account, name: 'Phone Support') }
  let(:release) { create(:voice_agent_release, account: account, voice_agent: voice_agent, revision: 3) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      contact: conversation.contact,
      provider: :livekit,
      status: 'completed',
      duration_seconds: 95,
      voice_agent_release: release,
      meta: {
        'from_number' => '+905551112233',
        'handoff_status' => 'accepted',
        'summary' => { 'text' => 'Caller shared test@example.com about an order.', 'model' => 'hidden-model' }
      }
    )
  end

  it 'returns redacted owner-facing evidence without provider diagnostics' do
    evidence = {
      transcript_count: 1,
      action_count: 1,
      action_error_count: 1,
      recording_status: 'completed'
    }

    payload = described_class.new(
      call.reload,
      voice_agent_releases_by_id: { release.id => release },
      evidence: evidence
    ).payload

    expect(payload).to include(
      status: 'completed',
      outcome: 'human_handoff',
      duration_seconds: 95,
      summary: 'Caller shared [email redacted] about an order.',
      transcript_count: 1,
      action_count: 1,
      action_error_count: 1,
      recording_status: 'completed'
    )
    expect(payload[:voice_agent]).to eq(id: voice_agent.id, name: 'Phone Support', revision: 3)
    expect(payload).not_to have_key(:provider)
    expect(payload.to_json).not_to include('hidden-model')
  end

  it 'uses the batched assistant lookup for calls created before releases were pinned' do
    call.update!(voice_agent_release: nil, meta: call.meta.merge('voice_agent_id' => voice_agent.id))

    payload = described_class.new(call, voice_agents_by_id: { voice_agent.id => voice_agent }).payload

    expect(payload[:voice_agent]).to eq(id: voice_agent.id, name: 'Phone Support')
  end
end
