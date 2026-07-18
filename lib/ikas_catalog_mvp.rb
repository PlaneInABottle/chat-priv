# frozen_string_literal: true

require 'json'
require 'pathname'

module IkasCatalogMvp
  ROOT_DIR = Pathname.new(Dir.pwd).join('tmp/ikas_catalog_mvp').freeze
  DEFAULT_GRAPHQL_URL = 'https://api.myikas.com/api/v1/admin/graphql'
  TOKEN_PATH = '/api/admin/oauth/token'

  class Error < StandardError; end
end

require_relative 'ikas_catalog_mvp/text'
require_relative 'ikas_catalog_mvp/catalog_client'
require_relative 'ikas_catalog_mvp/raw_sync'
require_relative 'ikas_catalog_mvp/product_link_builder'
require_relative 'ikas_catalog_mvp/image_link_builder'
require_relative 'ikas_catalog_mvp/normalizer'
require_relative 'ikas_catalog_mvp/sqlite_builder'
require_relative 'ikas_catalog_mvp/query_parser'
require_relative 'ikas_catalog_mvp/query_engine'
require_relative 'ikas_catalog_mvp/catalog_evaluator'
