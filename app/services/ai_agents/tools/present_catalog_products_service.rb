# frozen_string_literal: true

class AiAgents::Tools::PresentCatalogProductsService
  Request = Struct.new(:mode, :ids, :customer_message, :continue_previous, keyword_init: true)

  PRODUCT_MODE = 'products'
  GALLERY_MODE = 'product_gallery'
  MAX_PRODUCTS = 3
  MAX_GALLERY_IMAGES = 3
  CUSTOMER_MESSAGE_LIMIT = 400

  def initialize(account:, tool_events: [], resolver: nil, conversation: nil, **_context)
    @account = account
    @tool_events = Array(tool_events)
    @resolver = resolver || Integrations::Ikas::Catalog::ItemImagesResolver.new(account: account)
    @conversation = conversation
  end

  def call(args:)
    request = build_request(args)
    error_code = request_error(request)
    return error_result(error_code) if error_code

    present(request)
  end

  private

  attr_reader :tool_events, :resolver, :conversation

  def present(request)
    continuation = continuation_for(request.mode, request.ids) if request.continue_previous
    error_code = continuation_error(request, continuation)
    return error_result(error_code) if error_code

    resolved_items = resolver.resolve(item_ids: request.ids)
    error_code = resolved_items_error(resolved_items, request.ids)
    return error_result(error_code) if error_code

    presentation_items = resolved_items.map do |item|
      presentation_item(item, request.mode, image_offset: gallery_image_offset(request, item))
    end
    return error_result('no_more_catalog_images') if presentation_items.any? { |item| item[:images].empty? }

    success_result(request, presentation_items, continuation)
  end

  def build_request(args)
    normalized = args.to_h.deep_stringify_keys
    Request.new(
      mode: normalized['mode'].to_s,
      ids: Array(normalized['catalog_item_ids']).map { |id| id.to_s.strip },
      customer_message: normalized['customer_message'].to_s.strip,
      continue_previous: normalized['continue_previous'] == true
    )
  end

  def request_error(request)
    basic_request_error(request) || catalog_request_error(request.ids)
  end

  def basic_request_error(request)
    return 'invalid_mode' unless request.mode.in?([PRODUCT_MODE, GALLERY_MODE])
    return 'invalid_customer_message' unless valid_customer_message?(request.customer_message)
    return 'invalid_product_count' unless valid_item_count?(request.ids, request.mode)
  end

  def catalog_request_error(ids)
    return 'unknown_catalog_item' unless ids.all? { |id| available_candidates.key?(id) }
    return 'catalog_images_unavailable' unless ids.all? { |id| available_candidates.dig(id, 'image', 'available') == true }
  end

  def resolved_items_error(items, requested_ids)
    return 'catalog_changed' unless items.pluck(:item_id) == requested_ids
    return 'catalog_images_unavailable' if items.any? { |item| normalized_images(item).empty? }
  end

  def continuation_error(request, continuation)
    return unless request.continue_previous
    return 'invalid_continuation' if continuation.blank?
    return 'repeated_catalog_item' if request.mode == PRODUCT_MODE && request.ids.intersect?(presented_item_ids)
  end

  def gallery_image_offset(req, item) = req.continue_previous && req.mode == GALLERY_MODE ? presented_image_count(item.fetch(:item_id)) : 0

  def success_result(request, items, continuation)
    {
      status: 'ok',
      terminal_action: AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL,
      customer_message: request.customer_message,
      presentation: {
        id: SecureRandom.uuid,
        content_type: 'catalog_products',
        mode: request.mode,
        continuation_of: continuation&.fetch(:id, nil),
        items: items
      }.compact
    }
  end

  def valid_customer_message?(message) = message.present? && message.length <= CUSTOMER_MESSAGE_LIMIT

  def valid_item_count?(ids, mode)
    return false if ids.any?(&:blank?) || ids.uniq.length != ids.length
    return ids.one? if mode == GALLERY_MODE

    ids.length.between?(1, MAX_PRODUCTS)
  end

  def available_candidates
    @available_candidates ||= extract_candidates(latest_catalog_event&.dig('result')).index_by { |candidate| candidate.fetch('item_id') }
  end

  def latest_catalog_event
    tool_events.reverse.find do |event|
      event['tool'] == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL && event['status'].to_s == 'ok'
    end
  end

  def extract_candidates(result)
    return [] unless result.is_a?(Hash)

    candidates = Array(result['candidates'])
    candidates + Array(result['queries']).flat_map { |child| extract_candidates(child) }
  end

  def presentation_item(item, mode, image_offset: 0)
    candidate = available_candidates.fetch(item.fetch(:item_id))
    images = presentation_images(item, mode, image_offset)

    {
      item_id: item.fetch(:item_id),
      display_name: candidate['display_name'].presence || item.fetch(:display_name),
      price: candidate['price'].presence || item[:price],
      link: candidate['link'].presence || item[:link],
      image_scope: images.first&.fetch(:scope, nil) || item[:image_scope],
      images: images.map { |image| image.fetch(:url) }
    }.compact
  end

  def presentation_images(item, mode, offset)
    images = normalized_images(item).drop(offset)
    mode == PRODUCT_MODE ? images.first(1) : images.first(MAX_GALLERY_IMAGES)
  end

  def presented_item_ids = @presented_item_ids ||= prior_presentations.flat_map { |presentation| presentation[:item_ids] }.uniq

  def presented_image_count(item_id) = prior_presentations.sum { |presentation| presentation.fetch(:image_counts, {}).fetch(item_id, 0) }

  def continuation_for(mode, ids)
    return prior_presentations.last if mode == PRODUCT_MODE

    prior_presentations.reverse.find { |presentation| presentation[:item_ids].include?(ids.first) }
  end

  def prior_presentations
    @prior_presentations ||= if conversation.is_a?(AiAgentTestConversation)
                               test_presentations
                             elsif conversation.respond_to?(:messages)
                               live_presentations
                             else
                               []
                             end
  end

  def test_presentations
    Array(conversation.messages).filter_map do |message|
      next unless message['terminal_action'] == AiAgents::Config::PRESENT_CATALOG_PRODUCTS_TOOL

      presentation = message.dig('tool_result', 'presentation')
      next unless presentation.is_a?(Hash)

      items = Array(presentation['items'])
      {
        id: presentation['id'],
        item_ids: items.pluck('item_id'),
        image_counts: items.to_h { |item| [item['item_id'], Array(item['images']).length] }
      }
    end
  end

  def live_presentations
    messages = conversation.messages.outgoing.where(private: false).where(
      "(content_attributes #>> '{}')::jsonb #> '{ai_agent,catalog_presentation}' IS NOT NULL"
    ).reorder(:id)
    messages.group_by { |message| message.content_attributes.dig('ai_agent', 'catalog_presentation', 'id') }.filter_map do |id, group|
      next if id.blank?

      item_ids = group.filter_map { |message| message.content_attributes.dig('ai_agent', 'catalog_presentation', 'item_id') }.uniq
      image_counts = group.each_with_object(Hash.new(0)) do |message, counts|
        metadata = message.content_attributes.dig('ai_agent', 'catalog_presentation')
        counts[metadata['item_id']] += 1 if metadata['image_attached'] == true
      end
      { id: id, item_ids: item_ids, image_counts: image_counts }
    end
  end

  def normalized_images(item)
    Array(item[:images]).filter_map do |image|
      if image.is_a?(Hash)
        image = image.deep_symbolize_keys
        { url: image[:url], scope: image[:scope] }.compact if image[:url].present?
      elsif image.to_s.present?
        { url: image.to_s, scope: item[:image_scope] }
      end
    end
  end

  def error_result(error_code)
    {
      status: 'error',
      error_code: error_code,
      error_message: 'Catalog products could not be presented.',
      recoverable: true
    }
  end
end
