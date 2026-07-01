# frozen_string_literal: true

module Integrations::Ikas::OrderLookupQueries
  LIST_ORDERS = <<~GRAPHQL
    query IkasLookupOrders(
      $pagination: PaginationInput,
      $sort: String,
      $orderNumber: StringFilterInput,
      $id: StringFilterInput,
      $customerEmail: StringFilterInput,
      $customerId: StringFilterInput
    ) {
      listOrder(
        pagination: $pagination,
        sort: $sort,
        orderNumber: $orderNumber,
        id: $id,
        customerEmail: $customerEmail,
        customerId: $customerId
      ) {
        count
        hasNext
        limit
        page
        data {
          id
          orderNumber
          orderedAt
          status
          orderPackageStatus
          orderPaymentStatus
          totalFinalPrice
          currencyCode
          customerId
          orderPackages {
            id
            orderPackageNumber
            orderPackageFulfillStatus
            trackingInfo {
              cargoCompany
              trackingNumber
              trackingLink
            }
          }
          orderLineItems {
            id
            quantity
            variant {
              name
              sku
            }
          }
        }
      }
    }
  GRAPHQL

  RESOLVE_CUSTOMERS = <<~GRAPHQL
    query IkasResolveCustomers(
      $pagination: PaginationInput,
      $email: StringFilterInput,
      $phone: StringFilterInput,
      $search: String
    ) {
      listCustomer(pagination: $pagination, email: $email, phone: $phone, search: $search) {
        count
        data {
          id
          orderCount
        }
      }
    }
  GRAPHQL
end
