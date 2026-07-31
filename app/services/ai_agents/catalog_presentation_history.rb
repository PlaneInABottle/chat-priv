# frozen_string_literal: true

class AiAgents::CatalogPresentationHistory
  def initialize(conversation)
    @conversation = conversation
  end

  def latest = presentations.last

  def latest_for_item(item_id)
    presentations.reverse.find { |presentation| presentation[:item_ids].include?(item_id) }
  end

  def presented_item_ids
    presentations.flat_map { |presentation| presentation[:item_ids] }.uniq
  end

  def presented_image_keys(item_id)
    presentations.flat_map { |presentation| presentation.fetch(:image_keys, {}).fetch(item_id, []) }.to_set
  end

  private

  attr_reader :conversation

  def presentations
    @presentations ||= conversation.is_a?(AiAgentTestConversation) ? test_presentations : live_presentations
  end

  def test_presentations
    Array(conversation&.messages).filter_map do |message|
      next unless message['terminal_action'] == AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL

      presentation = message.dig('tool_result', 'presentation')
      next unless presentation.is_a?(Hash)

      items = Array(presentation['items'])
      presentation_summary(presentation['id'], items)
    end
  end

  def live_presentations
    return [] unless conversation.respond_to?(:messages)

    presentation_messages.group_by { |message| metadata(message)['id'] }.filter_map do |id, messages|
      live_presentation_summary(id, messages)
    end
  end

  def presentation_messages
    conversation.messages.outgoing.where(private: false).where(
      "(content_attributes #>> '{}')::jsonb #> '{ai_agent,catalog_presentation}' IS NOT NULL"
    ).reorder(:id)
  end

  def presentation_summary(id, items)
    {
      id: id,
      item_ids: items.pluck('item_id'),
      image_keys: items.to_h { |item| [item['item_id'], Array(item['images']).filter_map { |image| image_key_for(image) }] }
    }
  end

  def live_presentation_summary(id, messages)
    return if id.blank?

    delivered_messages = messages.select { |message| delivered_message?(message) }
    return if delivered_messages.empty?

    item_ids = delivered_messages.filter_map { |message| metadata(message)['item_id'] }.uniq
    image_keys = delivered_messages.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |message, keys|
      append_attached_image_key(keys, metadata(message))
    end
    { id: id, item_ids: item_ids, image_keys: image_keys }
  end

  def append_attached_image_key(keys, item_metadata)
    return unless item_metadata['image_attached'] == true && item_metadata['image_key'].present?

    keys[item_metadata['item_id']] << item_metadata['image_key']
  end

  def delivered_message?(message)
    return false if message.failed?

    delivery_status = metadata(message)['delivery_status']
    return delivery_status == 'delivered' if delivery_status.present?
    return message.source_id.present? if message.inbox.channel.is_a?(Channel::Whatsapp)

    true
  end

  def image_key_for(image)
    url = image.is_a?(Hash) ? image['url'] || image[:url] : image
    AiAgents::CatalogImageIdentity.for(url) if url.present?
  end

  def metadata(message)
    message.content_attributes.dig('ai_agent', 'catalog_presentation') || {}
  end
end
