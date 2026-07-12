require 'rails_helper'

RSpec.describe AiAgents::QualitySummary do
  let(:account) { create(:account) }
  let(:ai_agent) { create(:ai_agent, account: account, prompt: 'Live instructions') }

  it 'compares evaluation evidence and real activity by release' do
    older_release = create(
      :ai_agent_release,
      account: account,
      ai_agent: ai_agent,
      revision: 1,
      fingerprint: 'older-release-fingerprint'
    )
    live_release = create(:ai_agent_release, account: account, ai_agent: ai_agent, revision: 2)
    ai_agent.update!(current_release: live_release, prompt: 'Edited draft instructions', enabled: true)
    create_evaluation_evidence(live_release)
    create_live_activity(live_release)

    summary = described_class.new(ai_agent).call

    expect(summary.dig(:draft, :differs_from_live)).to be(true)
    expect(summary.dig(:draft, :evaluation)).to include(total_count: 2, passed_count: 2, pass_rate: 100)
    expect(summary[:releases].pluck(:id)).to eq([live_release.id, older_release.id])
    expect(summary[:releases].first).to include(
      current: true,
      live: true,
      evaluation: include(total_count: 4, passed_count: 3, pass_rate: 75),
      activity: { conversations: 2, ai_replies: 3, handoffs: 1, handoff_rate: 50 }
    )
    expect(summary[:releases].last).to include(
      live: false,
      evaluation: nil,
      activity: { conversations: 0, ai_replies: 0, handoffs: 0, handoff_rate: nil }
    )
  end

  def create_evaluation_evidence(live_release)
    create_evaluation_run(live_release.fingerprint, total: 4, passed: 3)
    create_evaluation_run(ai_agent.draft_fingerprint, total: 2, passed: 2)
  end

  def create_evaluation_run(fingerprint, total:, passed:)
    create(
      :ai_agent_evaluation_run,
      :completed,
      account: account,
      ai_agent: ai_agent,
      draft_fingerprint: fingerprint,
      total_count: total,
      passed_count: passed
    )
  end

  def create_live_activity(live_release)
    first_conversation = create(:conversation, account: account, ai_agent_release: live_release)
    second_conversation = create(
      :conversation,
      account: account,
      ai_agent_release: live_release,
      additional_attributes: {
        'ai_handoff_completed' => true,
        'ai_handoff_by_ai_agent_id' => ai_agent.id
      }
    )
    2.times { create_ai_reply(first_conversation) }
    create_ai_reply(second_conversation)
  end

  def create_ai_reply(conversation)
    create(
      :message,
      account: account,
      inbox: conversation.inbox,
      conversation: conversation,
      message_type: :outgoing,
      sender: ai_agent.agent_bot,
      private: false
    )
  end
end
