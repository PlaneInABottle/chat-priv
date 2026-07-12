# frozen_string_literal: true

class AiAgents::Tools::KnowledgeSearchService
  def initialize(knowledge_sources:, **_context)
    @knowledge_sources = Array(knowledge_sources).map { |source| source.to_h.deep_stringify_keys }
  end

  def call(args:)
    AiKnowledgeSources::Retriever.new(sources: knowledge_sources).call(
      query: args.to_h['query'],
      limit: args.to_h['limit']
    )
  end

  private

  attr_reader :knowledge_sources
end
