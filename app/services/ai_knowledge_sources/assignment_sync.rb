# frozen_string_literal: true

class AiKnowledgeSources::AssignmentSync
  MAX_SOURCES = 20

  def initialize(assistant:, source_ids:)
    @assistant = assistant
    @source_ids = Array(source_ids).map(&:to_i).select(&:positive?).uniq
  end

  def perform
    validate_source_limit!
    sources_by_id = assistant.account.ai_knowledge_sources.where(id: source_ids).index_by(&:id)
    missing_ids = source_ids - sources_by_id.keys
    raise ActiveRecord::RecordNotFound, "Knowledge sources not found: #{missing_ids.join(', ')}" if missing_ids.any?

    assistant.knowledge_sources = source_ids.filter_map { |id| sources_by_id[id] }
  end

  private

  attr_reader :assistant, :source_ids

  def validate_source_limit!
    return if source_ids.length <= MAX_SOURCES

    assistant.errors.add(:knowledge_source_ids, "can include up to #{MAX_SOURCES} sources")
    raise ActiveRecord::RecordInvalid, assistant
  end
end
