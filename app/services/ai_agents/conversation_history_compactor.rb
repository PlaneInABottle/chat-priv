# frozen_string_literal: true

class AiAgents::ConversationHistoryCompactor
  def initialize(messages)
    @messages = Array(messages)
  end

  def call
    normalized_messages.each_with_object([]) do |message, compacted|
      if merge_with_previous_presentation?(compacted.last, message)
        compacted.last[:content] = [compacted.last[:content], message[:content]].compact_blank.join("\n\n")
      else
        compacted << message
      end
    end
  end

  private

  attr_reader :messages

  def normalized_messages
    messages.filter_map do |message|
      message = message.to_h.deep_stringify_keys
      content = presentation_content(message) || message['content']
      next if content.blank?

      {
        role: message['role'],
        content: content,
        catalog_presentation_id: presentation_id(message)
      }.compact
    end
  end

  def presentation_content(message)
    presentation = message.dig('tool_result', 'presentation')
    return unless message['terminal_action'] == AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL && presentation.is_a?(Hash)

    product_lines = Array(presentation['items']).filter_map.with_index do |item, index|
      name = item['display_name'].to_s.strip
      next if name.blank?

      "#{index + 1}. #{name}"
    end
    [message['content'].to_s.strip.presence, product_lines.presence&.join("\n")].compact.join("\n\n")
  end

  def presentation_id(message)
    message.dig('catalog_presentation', 'id') || message.dig('tool_result', 'presentation', 'id')
  end

  def merge_with_previous_presentation?(previous, current)
    previous.present? && current[:catalog_presentation_id].present? &&
      previous[:role] == 'assistant' && current[:role] == 'assistant' &&
      previous[:catalog_presentation_id] == current[:catalog_presentation_id]
  end
end
