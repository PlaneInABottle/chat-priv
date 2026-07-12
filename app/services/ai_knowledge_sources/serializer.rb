# frozen_string_literal: true

class AiKnowledgeSources::Serializer
  PREVIEW_LENGTH = 160

  def initialize(source, include_content: false)
    @source = source
    @include_content = include_content
  end

  def payload
    assignments = source.assignments.to_a
    data = {
      id: source.id,
      name: source.name,
      source_type: source.source_type,
      content_preview: content_preview,
      character_count: character_count,
      assigned_ai_agent_ids: assistant_ids(assignments, 'AiAgent'),
      assigned_voice_agent_ids: assistant_ids(assignments, 'VoiceAgent'),
      created_at: source.created_at,
      updated_at: source.updated_at
    }
    data[:content] = source.content if include_content
    data
  end

  private

  attr_reader :source, :include_content

  def character_count
    return source[:character_count].to_i if source.has_attribute?('character_count')

    source.content.length
  end

  def content_preview
    preview = if source.has_attribute?('content_preview')
                source[:content_preview].to_s
              else
                source.content.first(PREVIEW_LENGTH)
              end
    character_count > preview.length ? "#{preview}..." : preview
  end

  def assistant_ids(assignments, assistant_type)
    assignments.filter_map { |assignment| assignment.assistant_id if assignment.assistant_type == assistant_type }.sort
  end
end
