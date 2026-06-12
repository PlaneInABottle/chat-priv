# frozen_string_literal: true

require 'optparse'
require_relative '../ikas_catalog_mvp'

module IkasCatalogMvp
  class CLI
    def self.call(argv)
      new(argv).call
    end

    def initialize(argv)
      @argv = argv.dup
    end

    def call
      command = argv.shift
      case command
      when 'sync' then sync
      when 'build' then build
      when 'query' then query
      when 'eval' then evaluate
      else
        warn usage
        1
      end
    rescue Error, OptionParser::ParseError, KeyError => e
      warn({ 'error' => e.message }.to_json)
      1
    end

    private

    attr_reader :argv

    def sync
      options = {
        store_url: ENV.fetch('IKAS_STORE_URL', nil),
        client_id: ENV.fetch('IKAS_CLIENT_ID', nil),
        client_secret: ENV.fetch('IKAS_CLIENT_SECRET', nil),
        graphql_url: ENV.fetch('IKAS_API_URL', nil),
        output_root: ROOT_DIR.to_s
      }
      OptionParser.new do |parser|
        parser.on('--store-url VALUE') { |value| options[:store_url] = value }
        parser.on('--client-id VALUE') { |value| options[:client_id] = value }
        parser.on('--client-secret VALUE') { |value| options[:client_secret] = value }
        parser.on('--api-url VALUE') { |value| options[:graphql_url] = value }
        parser.on('--output-root VALUE') { |value| options[:output_root] = value }
      end.parse!(argv)

      require_option!(options, :store_url)
      require_option!(options, :client_id)
      require_option!(options, :client_secret)

      client = CatalogClient.new(
        store_url: options.fetch(:store_url),
        client_id: options.fetch(:client_id),
        client_secret: options.fetch(:client_secret),
        graphql_url: options[:graphql_url].to_s.empty? ? DEFAULT_GRAPHQL_URL : options[:graphql_url]
      )
      puts JSON.pretty_generate(RawSync.new(client: client, output_root: options.fetch(:output_root)).perform)
      0
    end

    def build
      options = {}
      OptionParser.new do |parser|
        parser.on('--snapshot-dir VALUE') { |value| options[:snapshot_dir] = value }
        parser.on('--sqlite-path VALUE') { |value| options[:sqlite_path] = value }
      end.parse!(argv)

      require_option!(options, :snapshot_dir)
      puts JSON.pretty_generate(SqliteBuilder.new(snapshot_dir: options.fetch(:snapshot_dir), sqlite_path: options[:sqlite_path]).build)
      0
    end

    def query
      options = { limit: QueryEngine::DEFAULT_LIMIT }
      OptionParser.new do |parser|
        parser.on('--sqlite-path VALUE') { |value| options[:sqlite_path] = value }
        parser.on('--text VALUE') { |value| options[:text] = value }
        parser.on('--limit VALUE') { |value| options[:limit] = value.to_i }
      end.parse!(argv)

      require_option!(options, :sqlite_path)
      require_option!(options, :text)
      puts JSON.pretty_generate(QueryEngine.new(sqlite_path: options.fetch(:sqlite_path)).query(options.fetch(:text), limit: options.fetch(:limit)))
      0
    end

    def evaluate
      options = { limit: QueryEngine::DEFAULT_LIMIT, format: CatalogEvaluator::DEFAULT_FORMAT }
      OptionParser.new do |parser|
        parser.on('--sqlite-path VALUE') { |value| options[:sqlite_path] = value }
        parser.on('--cases VALUE') { |value| options[:cases_path] = value }
        parser.on('--limit VALUE') { |value| options[:limit] = value.to_i }
        parser.on('--format VALUE') { |value| options[:format] = value }
      end.parse!(argv)

      require_option!(options, :sqlite_path)
      require_option!(options, :cases_path)
      report = CatalogEvaluator.new(
        sqlite_path: options.fetch(:sqlite_path),
        cases_path: options.fetch(:cases_path),
        limit: options.fetch(:limit)
      ).evaluate
      puts CatalogEvaluator.render(report, format: options.fetch(:format))
      report.fetch('status') == 'passed' ? 0 : 1
    end

    def require_option!(options, key)
      raise KeyError, "missing required option: #{key}" if options[key].to_s.empty?
    end

    def usage
      <<~TEXT
        Usage:
          bin/ikas_catalog_mvp sync --store-url STORE --client-id ID --client-secret SECRET [--api-url URL] [--output-root DIR]
          bin/ikas_catalog_mvp build --snapshot-dir DIR [--sqlite-path FILE]
          bin/ikas_catalog_mvp query --sqlite-path FILE --text TEXT [--limit N]
          bin/ikas_catalog_mvp eval --sqlite-path FILE --cases FILE [--format json|markdown] [--limit N]
      TEXT
    end
  end
end
