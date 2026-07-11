require 'rails_helper'

RSpec.describe Voice::TestCallImprovementBudgetJob do
  let(:started_at) { Time.zone.parse('2026-07-11 12:00:00 UTC') }
  let(:improvement_started_at) { started_at + 5.seconds }
  let(:call) do
    create(
      :call,
      provider: :livekit,
      status: 'in_progress',
      started_at: started_at,
      meta: {
        'test_call' => true,
        'ai_improvement_max_duration_seconds' => 20,
        'ai_improvement_started_at' => improvement_started_at.iso8601(3)
      }
    )
  end

  it 'finalizes an active test call at its reserved-credit deadline' do
    allow(Voice::CallFinalizer).to receive(:perform!)

    travel_to(improvement_started_at + 21.seconds) { described_class.perform_now(call) }

    expect(Voice::CallFinalizer).to have_received(:perform!).with(
      call: call,
      end_reason: 'ai_improvement_credit_limit',
      timing: { ended_at: improvement_started_at + 20.seconds, duration_seconds: 20 }
    )
  end

  it 'does nothing after the call already ended' do
    call.update!(status: 'completed')
    allow(Voice::CallFinalizer).to receive(:perform!)

    described_class.perform_now(call)

    expect(Voice::CallFinalizer).not_to have_received(:perform!)
  end

  it 'releases an abandoned test through no-answer finalization' do
    call.update!(meta: call.meta.except('ai_improvement_started_at'))
    allow(Voice::CallFinalizer).to receive(:perform!)

    described_class.perform_now(call)

    expect(Voice::CallFinalizer).to have_received(:perform!).with(
      call: call,
      status: 'no_answer',
      end_reason: 'participant_timeout',
      timing: {
        ended_at: started_at + described_class::PARTICIPANT_JOIN_GRACE,
        duration_seconds: 0
      }
    )
  end

  it 'reschedules itself when a worker receives the job before the deadline' do
    travel_to(improvement_started_at + 5.seconds) do
      expect { described_class.perform_now(call) }
        .to have_enqueued_job(described_class).with(call).at(improvement_started_at + 20.seconds)
    end
  end
end
