# frozen_string_literal: true

class AiKnowledgeSources::ReleaseAssignmentRestore
  def initialize(assistant:, snapshot:)
    @assistant = assistant
    @snapshot = snapshot.to_h
  end

  def perform
    snapshot_ids = snapshot.fetch('knowledge_sources', []).pluck('id')
    available_ids = assistant.account.ai_knowledge_sources.where(id: snapshot_ids).pluck(:id)
    AiKnowledgeSources::AssignmentSync.new(assistant: assistant, source_ids: available_ids).perform
  end

  private

  attr_reader :assistant, :snapshot
end
