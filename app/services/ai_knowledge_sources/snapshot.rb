# frozen_string_literal: true

class AiKnowledgeSources::Snapshot
  def self.for(assistant)
    assistant.knowledge_sources.order(:id).map do |source|
      {
        'id' => source.id,
        'name' => source.name,
        'source_type' => source.source_type,
        'content' => source.content,
        'updated_at' => source.updated_at&.iso8601(6)
      }
    end
  end
end
