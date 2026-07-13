require 'rails_helper'

RSpec.describe AiAgents::EvaluationRunner do
  let(:account) { create(:account, settings: { ai_agent_enabled: true }) }
  let(:ai_agent) { create(:ai_agent, account: account, prompt: 'Draft prompt') }
  let(:evaluation_case) { create(:ai_agent_evaluation_case, account: account, ai_agent: ai_agent) }
  let(:run) do
    create(
      :ai_agent_evaluation_run,
      account: account,
      ai_agent: ai_agent,
      prompt_snapshot: ai_agent.prompt,
      config_snapshot: {},
      knowledge_snapshot: [
        { 'id' => 14, 'name' => 'Returns', 'content' => 'Returns are accepted within 14 days.' }
      ],
      draft_fingerprint: ai_agent.draft_fingerprint
    )
  end
  let!(:result) do
    create(
      :ai_agent_evaluation_result,
      evaluation_run: run,
      evaluation_case: evaluation_case
    )
  end

  it 'runs the snapshot, records the judgment, and marks the same draft tested' do
    orchestrator = instance_double(
      AiAgents::Orchestrator,
      perform: {
        assistant_message: { 'content' => 'Delivery depends on location.' },
        tool_events: []
      }
    )
    judge = instance_double(AiAgents::EvaluationJudge)
    allow(AiAgents::Orchestrator).to receive(:new).and_return(orchestrator)
    allow(AiAgents::EvaluationJudge).to receive(:new).and_return(judge)
    allow(judge).to receive(:call).and_return(
      AiAgents::EvaluationJudge::Result.new(passed: true, reason: 'No exact date was promised.')
    )

    described_class.new(run: run).perform

    expect(AiAgents::Orchestrator).to have_received(:new).with(
      hash_including(
        prompt_override: 'Draft prompt',
        config_override: {},
        knowledge_sources_override: [
          { 'id' => 14, 'name' => 'Returns', 'content' => 'Returns are accepted within 14 days.' }
        ]
      )
    )
    expect(run.reload).to have_attributes(status: 'completed', claim_id: nil, passed_count: 1)
    expect(result.reload).to have_attributes(
      status: 'completed',
      passed: true,
      assistant_response: 'Delivery depends on location.',
      reason: 'No exact date was promised.'
    )
    expect(ai_agent.reload).to be_draft_tested
  end

  it 'records an individual evaluation failure and completes the remaining run' do
    allow(AiAgents::Orchestrator).to receive(:new).and_raise(StandardError, 'provider unavailable')

    described_class.new(run: run).perform

    expect(run.reload).to have_attributes(status: 'completed', passed_count: 0)
    expect(result.reload).to have_attributes(status: 'failed', passed: false)
    expect(result.reason).to include('provider unavailable')
    expect(ai_agent.reload).not_to be_draft_tested
  end

  it 'does not mark the draft tested when the evaluation completes with a failed judgment' do
    orchestrator = instance_double(
      AiAgents::Orchestrator,
      perform: {
        assistant_message: { 'content' => 'It will arrive on Tuesday.' },
        tool_events: []
      }
    )
    judge = instance_double(AiAgents::EvaluationJudge)
    allow(AiAgents::Orchestrator).to receive(:new).and_return(orchestrator)
    allow(AiAgents::EvaluationJudge).to receive(:new).and_return(judge)
    allow(judge).to receive(:call).and_return(
      AiAgents::EvaluationJudge::Result.new(passed: false, reason: 'The response promised an exact date.')
    )

    described_class.new(run: run).perform

    expect(run.reload).to have_attributes(status: 'completed', passed_count: 0)
    expect(result.reload).to have_attributes(status: 'completed', passed: false)
    expect(ai_agent.reload).not_to be_draft_tested
  end

  it 'does not execute a run already claimed by another worker' do
    run.update!(status: :running, started_at: 1.minute.ago)

    expect(AiAgents::Orchestrator).not_to receive(:new)

    described_class.new(run: run).perform

    expect(run.reload).to be_running
  end

  it 'resumes a stale run without repeating completed results' do
    result.update!(status: :completed, passed: true, assistant_response: 'Already complete')
    pending_case = create(:ai_agent_evaluation_case, account: account, ai_agent: ai_agent)
    create(:ai_agent_evaluation_result, evaluation_run: run, evaluation_case: pending_case)
    run.update!(status: :running, started_at: 20.minutes.ago, total_count: 2)
    orchestrator = instance_double(
      AiAgents::Orchestrator,
      perform: { assistant_message: { 'content' => 'New answer' }, tool_events: [] }
    )
    judge = instance_double(AiAgents::EvaluationJudge)
    allow(AiAgents::Orchestrator).to receive(:new).and_return(orchestrator)
    allow(AiAgents::EvaluationJudge).to receive(:new).and_return(judge)
    allow(judge).to receive(:call).and_return(AiAgents::EvaluationJudge::Result.new(passed: true, reason: 'Passed'))

    described_class.new(run: run).perform

    expect(AiAgents::Orchestrator).to have_received(:new).once
    expect(result.reload.assistant_response).to eq('Already complete')
    expect(run.reload).to have_attributes(status: 'completed', passed_count: 2)
  end

  it 'stops before judging or writing when another worker reclaims the run' do
    orchestrator = instance_double(AiAgents::Orchestrator)
    replacement_claim = nil
    allow(AiAgents::Orchestrator).to receive(:new).and_return(orchestrator)
    allow(orchestrator).to receive(:perform) do
      run.update!(started_at: 20.minutes.ago)
      replacement_claim = described_class.new(run: run).send(:claim_run)
      {
        assistant_message: { 'content' => 'An answer from the old worker.' },
        tool_events: []
      }
    end
    expect(AiAgents::EvaluationJudge).not_to receive(:new)

    described_class.new(run: run).perform

    expect(result.reload).to be_pending
    expect(run.reload).to have_attributes(status: 'running', claim_id: replacement_claim)
  end
end
