# frozen_string_literal: true

class AiAgents::CatalogPresentationDeliveryJob < MutexApplicationJob
  class DeliveryError < StandardError; end

  DELIVERY_LOCK_TTL = 2.minutes

  queue_as :high
  retry_on LockAcquisitionError, wait: 5.seconds, attempts: 25
  retry_on DeliveryError, wait: 10.seconds, attempts: 5

  def perform(conversation_id, presentation_id)
    with_lock(delivery_lock_key(conversation_id, presentation_id), DELIVERY_LOCK_TTL) do
      deliver_presentation(conversation_id, presentation_id)
    end
  end

  private

  def deliver_presentation(conversation_id, presentation_id)
    messages = presentation_messages(conversation_id, presentation_id)
    return if messages.empty?

    expected_total = presentation_metadata(messages.last).fetch('total').to_i
    expected_sequence = (1..expected_total).to_a
    actual_sequence = messages.map { |message| presentation_metadata(message).fetch('sequence').to_i }
    raise "Catalog presentation #{presentation_id} is incomplete" unless actual_sequence == expected_sequence

    messages.each { |message| deliver_message!(message) }
  end

  def deliver_message!(message)
    message.reload
    return if already_delivered?(message)

    previous_source_id = message.source_id
    SendReplyJob.perform_now(message.id)
    message.reload
    raise DeliveryError, "Catalog presentation message #{message.id} was not delivered" unless delivered?(message, previous_source_id)

    mark_delivered!(message)
  end

  def already_delivered?(message)
    presentation_metadata(message)['delivery_status'] == 'delivered' ||
      (whatsapp_message?(message) && message.source_id.present?)
  end

  def delivered?(message, previous_source_id)
    return !message.failed? unless whatsapp_message?(message)

    message.source_id.present? && (previous_source_id.blank? || !message.failed?)
  end

  def mark_delivered!(message)
    content_attributes = message.content_attributes.deep_dup
    content_attributes.dig('ai_agent', 'catalog_presentation')['delivery_status'] = 'delivered'
    content_attributes['external_error'] = nil if message.failed?

    updates = { content_attributes: content_attributes }
    updates[:status] = :sent if message.failed?
    message.update!(updates)
  end

  def whatsapp_message?(message)
    message.inbox.channel.is_a?(Channel::Whatsapp)
  end

  def delivery_lock_key(conversation_id, presentation_id)
    format(
      Redis::Alfred::AI_AGENT_CATALOG_PRESENTATION_DELIVERY_MUTEX,
      conversation_id: conversation_id,
      presentation_id: presentation_id
    )
  end

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
