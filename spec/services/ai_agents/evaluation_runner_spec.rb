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
      hash_including(prompt_override: 'Draft prompt', config_override: {})
    )
    expect(run.reload).to have_attributes(status: 'completed', passed_count: 1)
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
end
