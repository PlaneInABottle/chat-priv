# frozen_string_literal: true

class AiAgents::CatalogPresentationBuilder
  SUPPORTED_LOCALES = %w[en tr].freeze

  def initialize(assistant_message:, ai_agent:, trigger_message_id:, conversation: nil, media_preparer: nil)
    @assistant_message = assistant_message.deep_stringify_keys
    @ai_agent = ai_agent
    @trigger_message_id = trigger_message_id
    @conversation = conversation
    @media_preparer = media_preparer || AiAgents::CatalogImagePreparer.new
  end

  def call
    presentation = assistant_message.dig('tool_result', 'presentation') || {}
    items = Array(presentation['items']).map(&:deep_stringify_keys)
    raise ArgumentError, 'Catalog presentation has no items.' if items.empty?

    specs = items.flat_map { |item| item_specs(item) }
    decorate(specs, presentation)
  end

  private

  attr_reader :assistant_message, :ai_agent, :trigger_message_id, :conversation, :media_preparer

  def item_specs(item)
    image_urls = Array(item['images'])
    return [{ item: item }] if image_urls.empty?

    prepared_images = image_urls.filter_map do |image_url|
      prepared_image = prepare_image(image_url)
      { prepared_image: prepared_image, image_key: AiAgents::CatalogImageIdentity.for(image_url) } if prepared_image
    end
    return [{ item: item }] if prepared_images.empty?

    prepared_images.map { |prepared| { item: item, **prepared } }
  end

  def prepare_image(image_url)
    media_preparer.prepare(image_url)
  rescue AiAgents::CatalogImagePreparer::Error => e
    Rails.logger.warn("[AiAgents::CatalogImages] image unavailable: #{e.class}")
    nil
  end

  def decorate(specs, presentation)
    described_items = Set.new
    specs.each_with_index do |spec, index|
      include_details = described_items.add?(spec.dig(:item, 'item_id'))
      spec[:content] = caption(
        spec.fetch(:item),
        introduction: index.zero? ? assistant_message['content'] : nil,
        include_details: include_details,
        image_attached: spec[:prepared_image].present?
      )
      spec[:content_attributes] = message_attributes(spec, presentation, index, specs.length)
      spec[:message_params] = message_params(spec)
    end
  end

  def caption(item, introduction:, include_details:, image_attached:)
    lines = [
      introduction.to_s.strip.presence,
      linked_display_name(item.fetch('display_name'), item.dig('link', 'url'))
    ]
    return lines.compact.join("\n\n") unless include_details

    lines << localized_price(item['price'].to_h)
    lines << localized_maximum_dimensions(item['maximum_dimensions'].to_h)
    if image_attached && item['image_scope'] == 'representative_product'
      lines << I18n.t('ai_agents.catalog_products.representative_image', locale: locale)
    end
    lines.compact.join("\n\n")
  end

  def localized_price(price)
    amount = price['amount'] || price['reference_amount']
    return if amount.blank? || price['currency'].blank?

    I18n.t(
      'ai_agents.catalog_products.reference_price',
      amount: formatted_amount(amount),
      currency: price['currency'],
      locale: locale
    )
  end

  def localized_maximum_dimensions(dimensions)
    return if dimensions['width'].blank? || dimensions['height'].blank? || dimensions['unit'].blank?

    I18n.t(
      'ai_agents.catalog_products.maximum_dimensions',
      width: formatted_amount(dimensions['width']),
      height: formatted_amount(dimensions['height']),
      unit: dimensions['unit'],
      locale: locale
    )
  end

  def linked_display_name(display_name, url)
    return display_name if url.blank?

    "[#{display_name}](#{url})"
  end

  def message_attributes(spec, presentation, index, total)
    item = spec.fetch(:item)
    {
      ai_agent: {
        trigger_message_id: trigger_message_id,
        turn_telemetry: assistant_message['turn_telemetry'],
        catalog_presentation: catalog_presentation_attributes(item, presentation, spec, index, total)
      }.compact
    }
  end

  def message_params(spec)
    params = {
      content: spec.fetch(:content),
      private: false,
      sender_type: 'AgentBot',
      sender_id: ai_agent.agent_bot_id,
      content_attributes: spec.fetch(:content_attributes)
    }
    params[:attachments] = [spec[:prepared_image].uploaded_file] if spec[:prepared_image]
    params
  end

  def catalog_presentation_attributes(item, presentation, spec, index, total)
    {
      version: 1,
      id: presentation['id'],
      mode: presentation['mode'],
      sequence: index + 1,
      total: total,
      item_id: item['item_id'],
      display_name: item['display_name'],
      image_attached: spec[:prepared_image].present?,
      image_key: spec[:image_key],
      image_scope: item['image_scope']
    }.compact
  end

  def locale
    @locale ||= locale_candidates.filter_map { |candidate| normalized_locale(candidate) }.first || 'en'
  end

  def locale_candidates
    [
      current_conversation&.language,
      current_conversation&.additional_attributes&.dig('browser_language'),
      current_conversation&.contact&.additional_attributes&.dig('language_code'),
      ai_agent.account.locale
    ]
  end

  def current_conversation
    @current_conversation ||= conversation&.reload
  end

  def normalized_locale(value)
    language = value.to_s.downcase.tr('_', '-').split('-').first
    language if SUPPORTED_LOCALES.include?(language)
  end

  def formatted_amount(amount)
    numeric = amount.to_f
    numeric == numeric.to_i ? numeric.to_i : numeric
  end
end
