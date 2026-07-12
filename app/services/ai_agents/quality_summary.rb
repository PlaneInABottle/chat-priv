# frozen_string_literal: true

class AiAgents::QualitySummary
  RELEASE_LIMIT = 5

  def initialize(ai_agent)
    @ai_agent = ai_agent
  end

  def call
    {
      draft: draft_payload,
      releases: releases.map { |release| release_payload(release) }
    }
  end

  private

  attr_reader :ai_agent

  def releases
    @releases ||= ai_agent.releases.order(revision: :desc).limit(RELEASE_LIMIT).to_a
  end

  def draft_payload
    {
      differs_from_live: ai_agent.draft_changes?,
      evaluation: evaluation_payload(evaluation_runs_by_fingerprint[ai_agent.draft_fingerprint])
    }
  end

  def release_payload(release)
    conversation_count = conversation_counts.fetch(release.id, 0)
    handoff_count = handoff_counts.fetch(release.id, 0)
    current = release.id == ai_agent.current_release_id

    {
      id: release.id,
      revision: release.revision,
      current: current,
      live: current && ai_agent.enabled?,
      evaluation: evaluation_payload(evaluation_runs_by_fingerprint[release.fingerprint]),
      activity: {
        conversations: conversation_count,
        ai_replies: ai_reply_counts.fetch(release.id, 0),
        handoffs: handoff_count,
        handoff_rate: percentage(handoff_count, conversation_count)
      }
    }
  end

  def evaluation_payload(run)
    return unless run

    {
      id: run.id,
      total_count: run.total_count,
      passed_count: run.passed_count,
      pass_rate: percentage(run.passed_count, run.total_count),
      completed_at: run.completed_at
    }
  end

  def evaluation_runs_by_fingerprint
    @evaluation_runs_by_fingerprint ||= begin
      fingerprints = releases.map(&:fingerprint) << ai_agent.draft_fingerprint
      runs = ai_agent.evaluation_runs.completed
                     .where(draft_fingerprint: fingerprints.uniq)
                     .order(created_at: :desc)
      runs.each_with_object({}) { |run, memo| memo[run.draft_fingerprint] ||= run }
    end
  end

  def conversations
    @conversations ||= Conversation.where(ai_agent_release_id: releases.map(&:id))
  end

  def conversation_counts
    @conversation_counts ||= conversations.group(:ai_agent_release_id).count
  end

  def handoff_counts
    @handoff_counts ||= conversations
                        .where('additional_attributes @> ?', {
                          ai_handoff_completed: true,
                          ai_handoff_by_ai_agent_id: ai_agent.id
                        }.to_json)
                        .group(:ai_agent_release_id)
                        .count
  end

  def ai_reply_counts
    @ai_reply_counts ||= Message.joins(:conversation)
                                .reorder(nil)
                                .where(
                                  conversations: { ai_agent_release_id: releases.map(&:id) },
                                  sender_type: 'AgentBot',
                                  sender_id: ai_agent.agent_bot_id,
                                  private: false
                                )
                                .group('conversations.ai_agent_release_id')
                                .count
  end

  def percentage(numerator, denominator)
    return if denominator.zero?

    ((numerator.to_f / denominator) * 100).round
  end
end
