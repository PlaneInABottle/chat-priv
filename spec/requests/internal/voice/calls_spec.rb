require 'rails_helper'

RSpec.describe 'Internal voice calls API', type: :request do
  let(:account) { create(:account) }
  let(:api_channel) { create(:channel_api, account: account) }
  let(:inbox) { api_channel.inbox }
  let(:call) { Voice::TestCallBuilder.perform!(account: account, inbox: inbox) }
  let(:path) { "/internal/voice/calls/#{call.provider_call_id}/transcript" }

  before do
    allow(Voice::Livekit::AgentDispatchService).to receive(:perform).and_return({ 'status' => 'skipped' })
  end

  describe 'POST /internal/voice/calls/:provider_call_id/transcript' do
    it 'persists transcript with the internal token' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { role: 'caller', text: 'Merhaba', source: 'livekit_agent', external_segment_id: 'turn-1' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:created)
      expect(call.transcript_segments.count).to eq(1)
      expect(call.reload.transcript).to eq('caller: Merhaba')
    end

    it 'rejects missing or wrong tokens' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { role: 'caller', text: 'Merhaba' },
             headers: { 'X-Voice-Agent-Token' => 'wrong' },
             as: :json
      end

      expect(response).to have_http_status(:unauthorized)
      expect(call.transcript_segments.count).to eq(0)
    end

    it 'returns validation errors as json' do
      with_modified_env VOICE_AGENT_INTERNAL_TOKEN: 'secret' do
        post path,
             params: { role: 'caller', text: 'Merhaba', source: 'unknown_source' },
             headers: { 'X-Voice-Agent-Token' => 'secret' },
             as: :json
      end

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body['error']).to include('Source is not included in the list')
      expect(call.transcript_segments.count).to eq(0)
    end
  end
end
