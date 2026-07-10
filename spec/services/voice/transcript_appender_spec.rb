require 'rails_helper'

RSpec.describe Voice::TranscriptAppender do
  let(:account) { create(:account, settings: { voice_ai_enabled: true }) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:voice_agent) { create(:voice_agent, account: account) }
  let!(:voice_inbox_setting) { create(:voice_inbox_setting, account: account, inbox: inbox, voice_agent: voice_agent) }
  let(:call) { Voice::TestCallBuilder.perform!(account: account, inbox: inbox, voice_agent: voice_agent) }

  before do
    allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return({ 'status' => 'skipped' })
  end

  describe '.perform!' do
    it 'persists transcript segments and refreshes call transcript text' do
      segment = described_class.perform!(
        call: call,
        role: 'caller',
        text: 'Merhaba',
        source: 'livekit_agent',
        external_segment_id: 'segment-1'
      )

      expect(segment).to be_persisted
      expect(call.reload.transcript).to eq('caller: Merhaba')
    end

    it 'is idempotent when an external segment id is provided' do
      first = described_class.perform!(call: call, role: 'caller', text: 'Merhaba', source: 'livekit_agent', external_segment_id: 'segment-1')
      second = described_class.perform!(call: call, role: 'caller', text: 'Merhaba again', source: 'livekit_agent', external_segment_id: 'segment-1')

      expect(second).to eq(first)
      expect(call.transcript_segments.count).to eq(1)
      expect(call.reload.transcript).to eq('caller: Merhaba')
    end

    it 'marks the draft as tested after an assistant transcript segment' do
      voice_agent.update!(enabled: false, last_tested_at: nil)

      described_class.perform!(call: call, role: 'ai', text: 'Merhaba, nasil yardimci olabilirim?', source: 'livekit_agent')

      expect(voice_agent.reload.last_tested_at).to be_present
    end
  end
end
