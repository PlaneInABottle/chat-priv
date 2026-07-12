# frozen_string_literal: true

class Voice::Calls::ActivitySerializer
  def initialize(call, voice_agents_by_id: {}, voice_agent_releases_by_id: {}, evidence: {})
    @call = call
    @voice_agents_by_id = voice_agents_by_id
    @voice_agent_releases_by_id = voice_agent_releases_by_id
    @evidence = evidence
  end

  def payload
    identity_payload.merge(state_payload).merge(evidence_payload).compact
  end

  private

  attr_reader :call, :voice_agents_by_id, :voice_agent_releases_by_id, :evidence

  def identity_payload
    {
      id: call.id,
      conversation_id: call.conversation&.display_id,
      from_number: call.from_number,
      inbox: { id: call.inbox_id, name: call.inbox.name },
      voice_agent: voice_agent_payload
    }
  end

  def state_payload
    {
      status: call.display_status,
      outcome: outcome,
      handoff_status: call.handoff_status.presence || 'none',
      started_at: (call.started_at || call.created_at).iso8601,
      duration_seconds: call.duration_seconds
    }
  end

  def evidence_payload
    {
      summary: summary_text,
      transcript_count: evidence.fetch(:transcript_count, 0),
      action_count: evidence.fetch(:action_count, 0),
      action_error_count: evidence.fetch(:action_error_count, 0),
      recording_status: evidence.fetch(:recording_status, 'disabled')
    }
  end

  def outcome
    return 'failed' if call.status == 'failed'
    return 'no_answer' if call.status == 'no_answer'
    return 'human_handoff' if call.handoff_status.in?(%w[requested accepted])
    return 'completed' if call.status == 'completed'

    'active'
  end

  def voice_agent_payload
    release = voice_agent_releases_by_id[call.voice_agent_release_id]
    return release_payload(release) if release

    voice_agent = voice_agents_by_id[call.meta&.fetch('voice_agent_id', nil).to_i]
    return unless voice_agent

    { id: voice_agent.id, name: voice_agent.name }
  end

  def release_payload(release)
    {
      id: release.voice_agent_id,
      name: release.voice_agent.name,
      revision: release.revision
    }
  end

  def summary_text
    summary = call.summary
    text = summary.is_a?(Hash) ? summary['text'] : summary
    AiAgents::PrivacyRedactor.redact_text(text) if text.present?
  end
end
