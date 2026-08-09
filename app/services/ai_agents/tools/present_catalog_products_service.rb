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
    @presentation_history = AiAgents::CatalogPresentationHistory.new(conversation)
  end

  def call(args:)
    request = build_request(args)
    error_code = request_error(request)
    return error_result(error_code) if error_code

    present(request)
  end

  private

  attr_reader :tool_events, :resolver, :presentation_history

  def present(request)
    continuation = continuation_for(request.mode, request.ids) if request.continue_previous
    error_code = continuation_error(request, continuation)
    return error_result(error_code) if error_code

    resolved_items = resolver.resolve(item_ids: request.ids)
    error_code = resolved_items_error(resolved_items, request.ids)
    return error_result(error_code) if error_code

    presentation_items = resolved_items.map { |item| presentation_item(item, request) }
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
    return 'repeated_catalog_item' if request.mode == PRODUCT_MODE && request.ids.intersect?(presentation_history.presented_item_ids)
  end

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

  def presentation_item(item, request)
    candidate = available_candidates.fetch(item.fetch(:item_id))
    images = presentation_images(item, request)

    {
      item_id: item.fetch(:item_id),
      display_name: candidate['display_name'].presence || item.fetch(:display_name),
      price: candidate['price'].presence || item[:price],
      link: candidate['link'].presence || item[:link],
      maximum_dimensions: maximum_dimensions(candidate),
      image_scope: images.first&.fetch(:scope, nil) || item[:image_scope],
      images: images.map { |image| image.fetch(:url) }
    }.compact
  end

  def maximum_dimensions(candidate)
    options = Array(candidate.dig('configuration', 'options'))
    width, height = %w[width height].map { |axis| dimension_option(options, axis) }
    return unless shared_dimension_bounds?(width, height)

    { width: width['max'], height: height['max'], unit: width['unit'] }
  end

  def dimension_option(options, axis)
    options.find { |option| option['type'] == 'dimension' && option['axis'] == axis }
  end

  def shared_dimension_bounds?(width, height)
    width&.dig('max').present? && height&.dig('max').present? && width['unit'].present? && width['unit'] == height['unit']
  end

  def presentation_images(item, request)
    images = normalized_images(item)
    if request.continue_previous && request.mode == GALLERY_MODE
      shown_keys = presentation_history.presented_image_keys(item.fetch(:item_id))
      images = images.reject { |image| shown_keys.include?(image.fetch(:key)) }
    end
    request.mode == PRODUCT_MODE ? images.first(1) : images.first(MAX_GALLERY_IMAGES)
  end

  def continuation_for(mode, ids)
    return presentation_history.latest if mode == PRODUCT_MODE

    presentation_history.latest_for_item(ids.first)
  end

  def normalized_images(item)
    Array(item[:images]).filter_map do |image|
      if image.is_a?(Hash)
        image = image.deep_symbolize_keys
        { url: image[:url], scope: image[:scope], key: AiAgents::CatalogImageIdentity.for(image[:url]) }.compact if image[:url].present?
      elsif image.to_s.present?
        { url: image.to_s, scope: item[:image_scope], key: AiAgents::CatalogImageIdentity.for(image) }
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
