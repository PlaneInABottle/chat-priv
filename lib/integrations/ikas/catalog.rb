# frozen_string_literal: true

require_relative '../../ikas_catalog_mvp'

module Integrations
  module Ikas
    module Catalog
      ROOT_DIR = Rails.root.join('tmp/ikas_catalog').freeze
      DEFAULT_GRAPHQL_URL = IkasCatalogMvp::DEFAULT_GRAPHQL_URL
      TOKEN_PATH = IkasCatalogMvp::TOKEN_PATH

      Error = IkasCatalogMvp::Error
      Text = IkasCatalogMvp::Text
      Client = IkasCatalogMvp::CatalogClient
      RawSync = IkasCatalogMvp::RawSync
      Normalizer = IkasCatalogMvp::Normalizer
      SqliteBuilder = IkasCatalogMvp::SqliteBuilder
      QueryParser = IkasCatalogMvp::QueryParser
      QueryEngine = IkasCatalogMvp::QueryEngine
    end
  end
end
