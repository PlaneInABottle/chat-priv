# frozen_string_literal: true

require 'uri'

module IkasCatalogMvp
  class ProductLinkBuilder
    def initialize(storefronts:)
      @storefronts = Array(storefronts)
    end

    def eligible_storefronts
      @eligible_storefronts ||= storefronts.filter_map { |storefront| normalize_storefront(storefront) }
    end

    def product_visible?(product)
      !visible_storefront_for(product).nil?
    end

    def link_fields_for(product, option_facets: [])
      storefront = visible_storefront_for(product)
      slug = product.dig('metaData', 'slug').to_s.strip
      return {} unless storefront && !slug.empty?

      canonical_url = trusted_canonical_url(product, storefront)
      url = canonical_url || constructed_url(slug, storefront)
      return {} if url.to_s.empty?

      selected_url = option_facets.any? ? variant_option_url(url, option_facets) : url
      source = canonical_url ? 'ikas_canonical' : 'ikas_slug'
      source = "#{source}_variant_options" if selected_url != url

      {
        'product_url' => selected_url,
        'product_slug' => slug,
        'product_url_source' => source,
        'storefront_id' => storefront.fetch('id'),
        'storefront_domain' => storefront.fetch('domain'),
        'storefront_sales_channel_id' => storefront.fetch('sales_channel_id'),
        'storefront_currency_code' => storefront['currency_code'],
        'storefront_currency_symbol' => storefront['currency_symbol']
      }
    end

    private

    attr_reader :storefronts

    def normalize_storefront(storefront)
      return unless storefront_available?(storefront)

      domain = domain_for(storefront)
      sales_channel_id = storefront['salesChannelId'].to_s
      return if domain.to_s.empty? || sales_channel_id.empty?

      routing = storefront_routing_for(storefront, domain)
      {
        'id' => storefront.fetch('id'),
        'name' => storefront['name'],
        'sales_channel_id' => sales_channel_id,
        'domain' => domain,
        'path' => normalize_path(routing&.[]('path')),
        'currency_code' => routing&.[]('currencyCode'),
        'currency_symbol' => routing&.[]('currencySymbol')
      }
    end

    def storefront_available?(storefront)
      !deleted_flag?(storefront['deleted'])
    end

    def deleted_flag?(deleted)
      %w[1 true].include?(deleted.to_s.downcase)
    end

    def domain_for(storefront)
      domains = Array(storefront['domains'])
      selected = domains.find { |domain| domain['isDefault'] == true } || domains.first
      normalize_host(selected&.[]('name')) || normalize_host(selected&.[]('redirectDomainName'))
    end

    def storefront_routing_for(storefront, domain)
      Array(storefront['routings']).find { |row| normalize_host(row['domain']) == domain } ||
        Array(storefront['routings']).first
    end

    def visible_storefront_for(product)
      sales_channel_ids = Array(product['salesChannelIds']).map(&:to_s)
      hidden_sales_channel_ids = Array(product['hiddenSalesChannelIds']).map(&:to_s)
      return if sales_channel_ids.empty?

      eligible_storefronts.find do |storefront|
        sales_channel_id = storefront.fetch('sales_channel_id')
        sales_channel_ids.include?(sales_channel_id) && !hidden_sales_channel_ids.include?(sales_channel_id)
      end
    end

    def trusted_canonical_url(product, storefront)
      Array(product.dig('metaData', 'canonicals')).find do |url|
        canonical_host_matches?(url, storefront.fetch('domain'))
      end
    end

    def canonical_host_matches?(url, expected_domain)
      uri = URI.parse(url.to_s)
      %w[http https].include?(uri.scheme) && uri.host.to_s.downcase == expected_domain
    rescue URI::InvalidURIError
      false
    end

    def constructed_url(slug, storefront)
      path = [storefront['path'], slug.delete_prefix('/')].compact.reject(&:empty?).join('/')
      "https://#{storefront.fetch('domain')}/#{path}"
    end

    def variant_option_url(url, option_facets)
      uri = URI.parse(url)
      option_params = option_facets.filter_map do |facet|
        key = facet['key'].to_s.strip
        value = facet['value'].to_s.strip
        next if key.empty? || value.empty?

        [quoted_option_key(key), value]
      end
      return url if option_params.empty?

      existing_params = URI.decode_www_form(uri.query.to_s)
      uri.query = URI.encode_www_form(existing_params + option_params)
      uri.to_s
    rescue URI::InvalidURIError
      url
    end

    def quoted_option_key(key)
      normalized = key.delete_prefix('"').delete_suffix('"')
      %("#{normalized}")
    end

    def normalize_host(value)
      candidate = value.to_s.strip
      return if candidate.empty?

      candidate = "https://#{candidate}" unless candidate.match?(%r{\Ahttps?://}i)
      host = URI.parse(candidate).host.to_s.downcase.delete_suffix('.')
      host.empty? ? nil : host
    rescue URI::InvalidURIError
      nil
    end

    def normalize_path(value)
      path = value.to_s.split('/').reject(&:empty?).join('/')
      path.empty? ? nil : path
    end
  end
end
