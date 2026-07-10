require 'rails_helper'

RSpec.describe AiDataRetention::PurgeService do
  let(:account) do
    create(
      :account,
      ai_agent_data_retention_days: 30,
      voice_ai_data_retention_days: 30
    )
  end

  describe '#perform' do
    it 'purges expired text AI payloads without removing usage accounting', :aggregate_failures do
      ai_agent = create(:ai_agent, account: account)
      old_call = create(:ai_agent_llm_call, account: account, ai_agent: ai_agent, created_at: 40.days.ago)
      recent_call = create(:ai_agent_llm_call, account: account, ai_agent: ai_agent, created_at: 5.days.ago)
      old_tool = create(:ai_agent_tool_execution, account: account, ai_agent: ai_agent, created_at: 40.days.ago)
      old_test = create(:ai_agent_test_conversation, account: account, ai_agent: ai_agent, updated_at: 40.days.ago)
      evaluation_case = create(:ai_agent_evaluation_case, account: account, ai_agent: ai_agent)
      old_evaluation_run = create(
        :ai_agent_evaluation_run,
        :completed,
        account: account,
        ai_agent: ai_agent,
        created_at: 40.days.ago
      )
      old_evaluation_result = create(
        :ai_agent_evaluation_result,
        evaluation_run: old_evaluation_run,
        evaluation_case: evaluation_case
      )
      recent_evaluation_run = create(
        :ai_agent_evaluation_run,
        :completed,
        account: account,
        ai_agent: ai_agent,
        created_at: 5.days.ago
      )
      usage_event = create(:ai_agent_usage_event, account: account, ai_agent: ai_agent, created_at: 40.days.ago)

      result = described_class.new(account: account).perform(kind: 'text')

      expect(result['text']).to eq(llm_calls: 1, tool_executions: 1, test_conversations: 1, evaluation_runs: 1)
      expect(AiAgentLlmCall.exists?(old_call.id)).to be(false)
      expect(AiAgentToolExecution.exists?(old_tool.id)).to be(false)
      expect(AiAgentTestConversation.exists?(old_test.id)).to be(false)
      expect(AiAgentEvaluationRun.exists?(old_evaluation_run.id)).to be(false)
      expect(AiAgentEvaluationResult.exists?(old_evaluation_result.id)).to be(false)
      expect(AiAgentEvaluationCase.exists?(evaluation_case.id)).to be(true)
      expect(AiAgentEvaluationRun.exists?(recent_evaluation_run.id)).to be(true)
      expect(AiAgentLlmCall.exists?(recent_call.id)).to be(true)
      expect(AiAgentUsageEvent.exists?(usage_event.id)).to be(true)
    end

    it 'removes expired voice payloads while preserving call and message shells' do
      old_call = create(
        :call,
        account: account,
        status: 'completed',
        started_at: 40.days.ago,
        transcript: 'Sensitive transcript',
        meta: {
          'summary' => { 'text' => 'Sensitive summary' },
          'from_number' => '+905551112233',
          'last_voice_agent_payload' => { 'transcript' => 'Sensitive turn' },
          'handoff_status' => 'requested'
        }
      )
      message = create(
        :message,
        account: account,
        conversation: old_call.conversation,
        inbox: old_call.inbox,
        content_type: 'voice_call',
        content_attributes: {
          'data' => {
            'status' => 'completed',
            'summary' => { 'text' => 'Sensitive summary' },
            'recording' => { 'url' => 'https://recording.test/file' },
            'livekit_room_name' => 'sensitive-room'
          }
        }
      )
      old_call.update!(message: message)
      segment = old_call.transcript_segments.create!(
        account: account,
        conversation: old_call.conversation,
        role: 'caller',
        source: 'livekit_agent',
        text: 'Sensitive turn'
      )
      tool_event = old_call.voice_tool_events.create!(account: account, tool: 'human_handoff', status: 'executed', source: 'livekit_agent')
      recording = create(:voice_recording, account: account, call: old_call, object_key: nil, bucket: nil)
      recent_call = create(:call, account: account, status: 'completed', started_at: 5.days.ago, transcript: 'Recent transcript')
      active_call = create(:call, account: account, status: 'in_progress', started_at: 40.days.ago, transcript: 'Active transcript')

      result = described_class.new(account: account).perform(kind: 'voice')

      expect(result['voice']).to include(calls: 1, transcript_segments: 1, tool_events: 1, recordings: 1, recording_failures: 0)
      expect(old_call.reload).to have_attributes(transcript: nil, meta: { 'handoff_status' => 'requested' })
      expect(message.reload.content_attributes['data']).to eq('status' => 'completed')
      expect(
        [CallTranscriptSegment.exists?(segment.id), VoiceToolEvent.exists?(tool_event.id), VoiceRecording.exists?(recording.id)]
      ).to all(be(false))
      expect(recent_call.reload.transcript).to eq('Recent transcript')
      expect(active_call.reload.transcript).to eq('Active transcript')
    end
  end
end
