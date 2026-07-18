# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require 'time'

module IkasCatalogMvp
  class RawSync
    DATASETS = {
      'merchants' => :merchants,
      'categories' => :categories,
      'variant_types' => :variant_types,
      'product_attributes' => :product_attributes,
      'product_option_sets' => :product_option_sets,
      'storefronts' => :storefronts,
      'products' => :products
    }.freeze

    def initialize(client:, output_root: ROOT_DIR, clock: Time)
      @client = client
      @output_root = Pathname.new(output_root)
      @clock = clock
    end

    def perform
      run_id = SecureRandom.uuid
      run_dir = output_root.join(client.store_host || 'unknown-store', run_id)
      raw_dir = run_dir.join('raw')
      FileUtils.mkdir_p(raw_dir)

      manifest = base_manifest(run_id, run_dir)
      counts = {}

      DATASETS.each do |file_name, method_name|
        records = Array(client.public_send(method_name))
        write_jsonl(raw_dir.join("#{file_name}.jsonl"), records)
        counts[file_name] = records.length
      end

      manifest.merge!(
        'status' => 'completed',
        'completed_at' => clock.now.utc.iso8601,
        'counts' => counts
      )
      File.write(run_dir.join('manifest.json'), JSON.pretty_generate(manifest))
      manifest
    rescue StandardError => e
      manifest ||= base_manifest(run_id || SecureRandom.uuid, run_dir || output_root.join('failed'))
      FileUtils.mkdir_p(Pathname.new(manifest.fetch('run_dir')))
      manifest.merge!('status' => 'failed', 'completed_at' => clock.now.utc.iso8601, 'error' => e.message)
      File.write(Pathname.new(manifest.fetch('run_dir')).join('manifest.json'), JSON.pretty_generate(manifest))
      raise
    end

    private

    attr_reader :client, :output_root, :clock

    def base_manifest(run_id, run_dir)
      {
        'run_id' => run_id,
        'store_host' => client.store_host,
        'started_at' => clock.now.utc.iso8601,
        'status' => 'running',
        'run_dir' => run_dir.to_s
      }
    end

    def write_jsonl(path, records)
      File.open(path, 'w') do |file|
        records.each { |record| file.puts(Text.json(record)) }
      end
    end
  end
end
