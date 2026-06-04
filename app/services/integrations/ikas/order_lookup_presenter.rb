# frozen_string_literal: true

class Integrations::Ikas::OrderLookupPresenter
  def initialize(orders:, matched_by:, limit:)
    @orders = orders
    @matched_by = matched_by
    @limit = limit
  end

  def call
    result_type = unique_orders.one? ? 'show_order_status' : 'clarify_order'

    {
      status: 'ok',
      result_type: result_type,
      matched_by: matched_by,
      total_matches: unique_orders.length,
      orders: presented_orders(result_type),
      warnings: warnings_for(result_type)
    }
  end

  private

  attr_reader :orders, :matched_by, :limit

  def unique_orders
    @unique_orders ||= orders.uniq { |order| order['id'] }.sort_by { |order| -(order['orderedAt'].to_i) }
  end

  def presented_orders(result_type)
    unique_orders
      .first(limit)
      .map { |order| public_order_payload(order, detailed: result_type == 'show_order_status') }
  end

  def public_order_payload(order, detailed:)
    payload = {
      order_number: order['orderNumber'],
      ordered_at: timestamp_to_iso8601(order['orderedAt']),
      status: order['status'],
      payment_status: order['orderPaymentStatus'],
      package_status: order['orderPackageStatus']
    }
    return payload unless detailed

    payload.merge(
      total: { final_price: order['totalFinalPrice'], currency_code: order['currencyCode'] },
      packages: packages_payload(order['orderPackages']),
      items: items_payload(order['orderLineItems'])
    )
  end

  def packages_payload(packages)
    Array(packages).map do |package|
      tracking = package['trackingInfo'] || {}
      {
        package_number: package['orderPackageNumber'],
        fulfill_status: package['orderPackageFulfillStatus'],
        tracking: {
          cargo_company: tracking['cargoCompany'],
          tracking_number: tracking['trackingNumber'],
          tracking_link: tracking['trackingLink']
        }.compact
      }
    end
  end

  def items_payload(items)
    Array(items).first(5).map do |item|
      variant = item['variant'] || {}
      {
        name: variant['name'],
        sku: variant['sku'],
        quantity: item['quantity']
      }.compact
    end
  end

  def warnings_for(result_type)
    warnings = []
    warnings << 'multiple_orders_matched_ask_customer_to_confirm_order_number' if result_type == 'clarify_order'
    warnings << 'tracking_info_missing' if tracking_missing?(result_type)
    warnings
  end

  def tracking_missing?(result_type)
    return false unless result_type == 'show_order_status'

    packages_payload(unique_orders.first['orderPackages']).none? { |package| package[:tracking].present? }
  end

  def timestamp_to_iso8601(value)
    return if value.blank?

    timestamp = value.to_f
    timestamp /= 1000 if timestamp > 10_000_000_000
    Time.zone.at(timestamp).iso8601
  end
end
