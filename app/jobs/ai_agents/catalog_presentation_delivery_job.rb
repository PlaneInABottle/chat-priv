# frozen_string_literal: true

class AiAgents::CatalogPresentationDeliveryJob < ApplicationJob
  queue_as :high

  def perform(conversation_id, presentation_id)
    messages = presentation_messages(conversation_id, presentation_id)
    return if messages.empty?

    expected_total = presentation_metadata(messages.last).fetch('total').to_i
    expected_sequence = (1..expected_total).to_a
    actual_sequence = messages.map { |message| presentation_metadata(message).fetch('sequence').to_i }
    raise "Catalog presentation #{presentation_id} is incomplete" unless actual_sequence == expected_sequence

    messages.each { |message| SendReplyJob.perform_now(message.id) }
  end

  private

  def presentation_messages(conversation_id, presentation_id)
    metadata = { ai_agent: { catalog_presentation: { id: presentation_id.to_s } } }
    Conversation.find(conversation_id).messages.outgoing.where(private: false)
                .where("(content_attributes #>> '{}')::jsonb @> ?::jsonb", metadata.to_json)
                .reorder(:id)
                .sort_by { |message| presentation_metadata(message).fetch('sequence').to_i }
  end

  def presentation_metadata(message)
    message.content_attributes.dig('ai_agent', 'catalog_presentation') || {}
  end
end
