# frozen_string_literal: true

require 'httparty'
require 'uri'

module IkasCatalogMvp
  class CatalogClient
    DEFAULT_PAGE_LIMIT = 200

    LIST_CATEGORIES_QUERY = <<~GRAPHQL.freeze
      query IkasCatalogMvpCategories {
        listCategory {
          id
          name
          parentId
          categoryPath
          categoryPathItems { id name }
          salesChannelIds
          translations { locale name description }
        }
      }
    GRAPHQL

    LIST_VARIANT_TYPES_QUERY = <<~GRAPHQL.freeze
      query IkasCatalogMvpVariantTypes {
        listVariantType {
          id
          name
          selectionType
          translations { locale name values { id name } }
          values { id name colorCode thumbnailImageId }
        }
      }
    GRAPHQL

    LIST_PRODUCT_ATTRIBUTES_QUERY = <<~GRAPHQL.freeze
      query IkasCatalogMvpProductAttributes {
        listProductAttribute {
          id
          name
          description
          type
          options { id name }
          translations { locale name description options { id name } }
        }
      }
    GRAPHQL

    LIST_PRODUCT_OPTION_SETS_QUERY = <<~GRAPHQL.freeze
      query IkasCatalogMvpProductOptionSets {
        listProductOptionSet {
          id
          name
          options {
            id
            name
            type
            isOptional
            optionalText
            order
            price
            priceType
            textSettings { min max }
            selectSettings { type minSelect maxSelect values { id value price priceType } }
          }
        }
      }
    GRAPHQL

    LIST_PRODUCTS_QUERY = <<~GRAPHQL.freeze
      query IkasCatalogMvpProducts($page: Int!, $limit: Int!) {
        listProduct(pagination: { page: $page, limit: $limit }) {
          page
          limit
          hasNext
          count
          data {
            id
            name
            description
            shortDescription
            type
            productOptionSetId
            categoryIds
            salesChannelIds
            hiddenSalesChannelIds
            tagIds
            totalStock
            weight
            brand { id name }
            tags { id name }
            translations { locale name description }
            categories { id name parentId }
            attributes { productAttributeId productAttributeOptionId value imageIds }
            productVariantTypes { order variantTypeId variantValueIds }
            variants {
              id
              sku
              barcodeList
              isActive
              sellIfOutOfStock
              variantValueIds { variantTypeId variantValueId }
              prices {
                buyPrice
                currency
                currencyCode
                currencySymbol
                discountPrice
                priceListId
                sellPrice
              }
              stocks { id productId stockCount stockLocationId variantId }
              images { fileName imageId isMain isVideo order }
            }
          }
        }
      }
    GRAPHQL

    def initialize(client_id:, client_secret:, store_url:, graphql_url: DEFAULT_GRAPHQL_URL, page_limit: DEFAULT_PAGE_LIMIT)
      @client_id = client_id.to_s
      @client_secret = client_secret.to_s
      @store_url = store_url.to_s
      @graphql_url = graphql_url
      @page_limit = page_limit.to_i
    end

    def store_host
      @store_host ||= normalize_store_host
    end

    def categories
      execute_graphql(LIST_CATEGORIES_QUERY).fetch('listCategory')
    end

    def variant_types
      execute_graphql(LIST_VARIANT_TYPES_QUERY).fetch('listVariantType')
    end

    def product_attributes
      execute_graphql(LIST_PRODUCT_ATTRIBUTES_QUERY).fetch('listProductAttribute')
    end

    def product_option_sets
      execute_graphql(LIST_PRODUCT_OPTION_SETS_QUERY).fetch('listProductOptionSet')
    end

    def products
      page = 1
      rows = []

      loop do
        payload = execute_graphql(LIST_PRODUCTS_QUERY, { page: page, limit: page_limit }).fetch('listProduct')
        rows.concat(Array(payload['data']))
        break unless payload['hasNext']

        page += 1
      end

      rows
    end

    private

    attr_reader :client_id, :client_secret, :store_url, :graphql_url, :page_limit

    def execute_graphql(query, variables = nil)
      response = HTTParty.post(
        graphql_url,
        body: { query: query, variables: variables }.compact.to_json,
        headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{access_token}" },
        timeout: 30
      )
      parsed = JSON.parse(response.body)

      raise Error, "Ikas GraphQL HTTP #{response.code}" unless response.success?
      raise Error, "Ikas GraphQL errors: #{parsed['errors'].to_json}" if parsed['errors']

      parsed.fetch('data')
    rescue JSON::ParserError => e
      raise Error, "Ikas GraphQL parse failed: #{e.message}"
    end

    def access_token
      @access_token ||= begin
        raise Error, 'Ikas store URL is invalid' if store_host.nil?

        response = HTTParty.post(
          "https://#{store_host}#{TOKEN_PATH}",
          body: { grant_type: 'client_credentials', client_id: client_id, client_secret: client_secret },
          headers: { 'Content-Type' => 'application/x-www-form-urlencoded' },
          timeout: 15
        )

        raise Error, "Ikas token HTTP #{response.code}" unless response.success?

        parsed = JSON.parse(response.body)
        raise Error, 'Ikas token response missing access_token' if parsed['access_token'].to_s.empty?

        parsed.fetch('access_token')
      rescue JSON::ParserError => e
        raise Error, "Ikas token parse failed: #{e.message}"
      end
    end

    def normalize_store_host
      candidate = store_url.strip
      candidate = "https://#{candidate}" unless candidate.match?(%r{\Ahttps?://}i)
      uri = URI.parse(candidate)
      host = uri.host.to_s.downcase.delete_suffix('.')
      return nil unless host.match?(/\A[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.myikas\.com\z/)

      host
    rescue URI::InvalidURIError
      nil
    end
  end
end
