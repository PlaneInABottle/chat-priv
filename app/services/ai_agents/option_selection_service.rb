# frozen_string_literal: true

class AiAgents::OptionSelectionService
  class InvalidSelection < StandardError; end
  StaleSelection = Class.new(InvalidSelection)
  class AlreadySubmitted < StandardError; end

  def initialize(prompt_message:, selected_value:)
    @prompt_message = prompt_message
    @selected_value = selected_value.to_s
  end

  def selected_item
    validate_prompt!
    item = items.find { |candidate| candidate['value'].to_s == selected_value }
    raise InvalidSelection, 'Selected option is not available.' unless item

    validate_active_prompt! unless same_selection_submitted?

    item.slice('title', 'value')
  end

  def create_widget_response!(contact:)
    prompt_message.with_lock do
      validate_prompt!
      next existing_response if same_selection_submitted?

      raise AlreadySubmitted, 'This question has already been answered.' if submitted_values.present?

      validate_contact!(contact)
      validate_active_prompt!

      item = selected_item
      response = create_widget_message!(contact, item)
      record_submission!(item, response)
      response
    end
  end

  def record_response!(response_message)
    prompt_message.with_lock do
      validate_prompt!
      next existing_response if same_selection_submitted?

      raise AlreadySubmitted, 'This question has already been answered.' if submitted_values.present?

      validate_response_conversation!(response_message)
      validate_active_prompt!(excluding: response_message)

      item = selected_item
      response_message.content = item['title']
      response_message.content_attributes = response_content_attributes(item, existing: response_message.content_attributes)
      response_message.save! unless response_message.persisted?
      record_submission!(item, response_message)
      response_message
    end
  end

  private

  attr_reader :prompt_message, :selected_value

  def validate_prompt!
    valid = prompt_message.outgoing? && !prompt_message.private? && prompt_message.content_type == 'input_select' &&
            selection_metadata['version'].to_i == 1
    raise InvalidSelection, 'Message is not an active AI option prompt.' unless valid
  end

  def items
    Array(content_attributes['items']).map { |item| item.to_h.deep_stringify_keys }
  end

  def selection_metadata
    content_attributes.dig('ai_agent', 'selection').to_h.deep_stringify_keys
  end

  def submitted_values
    Array(content_attributes['submitted_values'])
  end

  def submitted_value
    submitted_values.first.to_h.deep_stringify_keys['value'].to_s
  end

  def submitted_response_id
    selection_metadata['response_message_id']
  end

  def same_selection_submitted?
    submitted_response_id.present? && submitted_value == selected_value
  end

  def validate_contact!(contact)
    return if prompt_message.conversation.contact_id == contact.id

    raise InvalidSelection, 'The selected option does not belong to this contact.'
  end

  def validate_response_conversation!(response_message)
    return if response_message.conversation_id == prompt_message.conversation_id

    raise InvalidSelection, 'The selected option does not belong to this conversation.'
  end

  def validate_active_prompt!(excluding: nil)
    later_messages = prompt_message.conversation.messages.incoming.where('messages.id > ?', prompt_message.id)
    later_messages = later_messages.where.not(id: excluding.id) if excluding&.persisted?
    return unless later_messages.exists?

    raise StaleSelection, 'This option prompt is no longer active.'
  end

  def create_widget_message!(contact, item)
    prompt_message.conversation.messages.create!(
      account_id: prompt_message.account_id,
      inbox_id: prompt_message.inbox_id,
      sender: contact,
      message_type: :incoming,
      content: item['title'],
      content_attributes: response_content_attributes(item)
    )
  end

  def existing_response
    prompt_message.conversation.messages.find(submitted_response_id)
  end

  def response_content_attributes(item, existing: {})
    existing.to_h.deep_stringify_keys.merge(
      'in_reply_to' => prompt_message.id,
      'selected_option' => item
    )
  end

  def record_submission!(item, response_message)
    attributes = content_attributes.deep_dup
    attributes['submitted_values'] = [item]
    attributes['ai_agent']['selection']['response_message_id'] = response_message.id
    prompt_message.update!(content_attributes: attributes)
  end

  def content_attributes
    prompt_message.content_attributes.to_h.deep_stringify_keys
  end
end
