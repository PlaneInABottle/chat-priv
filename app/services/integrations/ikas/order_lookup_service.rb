# frozen_string_literal: true

class Integrations::Ikas::OrderLookupService
  DEFAULT_LIMIT = 5
  MAX_LIMIT = 10
  CUSTOMER_LOOKUP_LIMIT = 5

  def initialize(account:, conversation: nil, identifiers: {}, limit: DEFAULT_LIMIT)
    @account = account
    @conversation = conversation
    @identifiers = identifiers.to_h.with_indifferent_access
    @order_identifier = identifiers_value(:order_identifier).to_s.strip
    @email = normalize_email(identifiers_value(:email))
    @phone = normalize_phone(identifiers_value(:phone))
    @limit = limit.to_i
  end

  def call
    integration_error = validation_error
    return integration_error if integration_error
    return needs_identifier_payload if lookup_identifiers_blank?

    lookup_result || no_match_payload
  rescue Integrations::Ikas::AdminApiClient::Error => e
    Rails.logger.error("[Integrations::Ikas::OrderLookupService] #{e.class}: #{e.message}")
    error_payload('ikas_order_lookup_failed', 'Ikas order lookup failed.')
  end

  private

  attr_reader :account, :conversation, :identifiers, :order_identifier, :email, :phone, :limit

  def lookup_result
    return lookup_by_order_identifier if order_identifier.present?

    lookup_by_email || lookup_by_phone
  end

  def validation_error
    unless account.feature_enabled?('ikas_integration')
      return error_payload('ikas_feature_disabled', 'Ikas integration is not enabled for this account.')
    end

    return error_payload('ikas_not_connected', 'Ikas integration is not connected.') unless connected_hook
    return error_payload('ikas_credentials_unavailable', 'Ikas credentials are unavailable.') if client_id.blank? || client_secret.blank?

    nil
  end

  def lookup_by_order_identifier
    return if order_identifier.blank?

    orders = orders_for(orderNumber: string_filter(order_identifier))
    orders = orders_for(id: string_filter(order_identifier)) if orders.empty? && uuid?(order_identifier)
    return if orders.empty?

    orders_payload(orders, matched_by: 'order_identifier')
  end

  def lookup_by_email
    email_value = email.presence || contact_email
    return if email_value.blank?

    orders = orders_for(customerEmail: string_filter(email_value))
    return if orders.empty?

    orders_payload(orders, matched_by: email.present? ? 'email' : 'contact_email')
  end

  def lookup_by_phone
    phone_value = phone.presence || contact_phone
    return if phone_value.blank?

    customer_ids = customer_ids_for_phone(phone_value)
    return if customer_ids.empty?

    orders = customer_ids.flat_map { |customer_id| orders_for(customerId: string_filter(customer_id)) }
    return if orders.empty?

    orders_payload(orders, matched_by: phone.present? ? 'phone' : 'contact_phone')
  end

  def orders_for(filters)
    response = client.execute(
      Integrations::Ikas::OrderLookupQueries::LIST_ORDERS,
      filters.merge(pagination: { page: 1, limit: clamped_limit }, sort: '-orderedAt')
    )
    Array(response.dig('listOrder', 'data'))
  end

  def customer_ids_for_phone(phone_value)
    phone_candidates(phone_value).flat_map do |candidate|
      exact_customer_ids = customer_ids_for(phone: string_filter(candidate))
      return exact_customer_ids if exact_customer_ids.present?

      next [] unless candidate.delete('^0-9').length >= 7

      customer_ids_for(search: candidate)
    end.uniq.first(CUSTOMER_LOOKUP_LIMIT)
  end

  def customer_ids_for(filters)
    response = client.execute(
      Integrations::Ikas::OrderLookupQueries::RESOLVE_CUSTOMERS,
      filters.merge(pagination: { page: 1, limit: CUSTOMER_LOOKUP_LIMIT })
    )
    Array(response.dig('listCustomer', 'data')).filter_map { |customer| customer['id'].presence }
  end

  def orders_payload(orders, matched_by:)
    Integrations::Ikas::OrderLookupPresenter.new(
      orders: orders,
      matched_by: matched_by,
      limit: clamped_limit
    ).call
  end

  def needs_identifier_payload
    {
      status: 'ok',
      result_type: 'needs_identifier',
      orders: [],
      warnings: ['ask_customer_for_order_number_phone_or_email']
    }
  end

  def no_match_payload
    {
      status: 'ok',
      result_type: 'no_match',
      orders: [],
      warnings: ['no_order_found_for_provided_identifier']
    }
  end

  def lookup_identifiers_blank?
    order_identifier.blank? && email.blank? && phone.blank? && contact_email.blank? && contact_phone.blank?
  end

  def connected_hook
    @connected_hook ||= begin
      status = Integrations::Ikas::ConnectionStatus.new(account: account).payload
      status[:state] == 'connected' ? status[:hook] : nil
    end
  end

  def client
    @client ||= Integrations::Ikas::AdminApiClient.new(
      store_host: connected_hook.reference_id,
      client_id: client_id,
      client_secret: client_secret
    )
  end

  def client_id
    connected_hook&.settings&.[]('client_id')
  end

  def client_secret
    @client_secret ||= connected_hook&.access_token
  rescue ActiveRecord::Encryption::Errors::Decryption
    nil
  end

  def contact_email
    @contact_email ||= normalize_email(conversation&.contact&.email)
  end

  def contact_phone
    @contact_phone ||= normalize_phone(conversation&.contact&.phone_number)
  end

  def normalize_email(value)
    value.to_s.strip.downcase.presence
  end

  def normalize_phone(value)
    normalized = value.to_s.strip.gsub(/[[:space:]\-()]/, '')
    normalized = "+#{normalized.delete_prefix('00')}" if normalized.start_with?('00')
    normalized.presence
  end

  def phone_candidates(value)
    candidates = [value]
    digits = value.delete('^0-9')
    candidates << "+#{digits}" if digits.present? && !value.start_with?('+')
    candidates.uniq
  end

  def string_filter(value)
    { eq: value }
  end

  def clamped_limit
    (limit.positive? ? limit : DEFAULT_LIMIT).clamp(1, MAX_LIMIT)
  end

  def uuid?(value)
    value.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i)
  end

  def identifiers_value(key)
    identifiers[key]
  end

  def error_payload(code, message)
    {
      status: 'error',
      error_code: code,
      error_message: message
    }
  end
end
