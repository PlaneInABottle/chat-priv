# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'
require_relative '../../../lib/ikas_catalog_mvp'

RSpec.describe IkasCatalogMvp::CatalogEvaluator do
  def with_cases(contents)
    Tempfile.create(['ikas-cases', '.yml']) do |file|
      file.write(contents)
      file.flush
      yield file.path
    end
  end

  def evaluator_for(cases_path, payloads)
    engine = Class.new do
      attr_reader :calls

      def initialize(payloads)
        @payloads = payloads
        @calls = []
      end

      def query(query, limit:)
        calls << { query: query, limit: limit }
        @payloads.fetch(query)
      end
    end.new(payloads)

    [described_class.new(sqlite_path: 'catalog.sqlite3', cases_path: cases_path, limit: 6, query_engine: engine), engine]
  end

  let(:candidate) do
    {
      'display_name' => 'Orjin Pliseli Perde Beyaz',
      'link' => { 'url' => 'https://store.example.com/perde' },
      'match_reasons' => ['matched color'],
      'evidence' => [{ 'source' => 'display_name', 'fact' => 'color', 'value' => 'BEYAZ', 'confidence' => 'medium' }]
    }
  end

  it 'passes cases that satisfy result, link, text, evidence, and bucket expectations' do
    cases = <<~YAML
      - id: beyaz_perde
        query: "beyaz perde"
        expect:
          result_type: ["show_candidates"]
          min_results: 1
          top_results_include: ["Orjin", "Beyaz"]
          require_links: true
          require_evidence:
            - fact: color
          min_buckets: 1
          bucket_labels_include: ["Plise"]
    YAML
    payload = {
      'result_type' => 'show_candidates',
      'parsed' => { 'terms' => ['perde'] },
      'candidates' => [candidate],
      'buckets' => [{ 'label' => 'Plise Perdeler', 'children' => [{ 'label' => 'Orjin Plise Perdeler' }] }]
    }

    with_cases(cases) do |path|
      evaluator, engine = evaluator_for(path, 'beyaz perde' => payload)
      report = evaluator.evaluate

      expect(report.fetch('status')).to eq('passed')
      expect(report.dig('summary', 'passed')).to eq(1)
      expect(report.dig('cases', 0, 'top_candidates', 0, 'link_url')).to eq('https://store.example.com/perde')
      expect(engine.calls.first).to eq({ query: 'beyaz perde', limit: 6 })
    end
  end

  it 'passes first result and candidate exclusion expectations' do
    cases = <<~YAML
      - id: strict_ranking
        query: "beyaz plise perde"
        expect:
          first_result_include: ["Orjin Pliseli Perde Beyaz"]
          candidate_text_excludes: ["Sineklik"]
    YAML
    payload = {
      'result_type' => 'show_candidates',
      'parsed' => { 'terms' => %w[beyaz perde] },
      'candidates' => [
        candidate,
        candidate.merge('display_name' => 'Blackout Perde Antrasit')
      ],
      'buckets' => []
    }

    with_cases(cases) do |path|
      evaluator, = evaluator_for(path, 'beyaz plise perde' => payload)
      report = evaluator.evaluate

      expect(report.fetch('status')).to eq('passed')
    end
  end

  it 'checks product grouping and customer-useful configuration data' do
    cases = <<~YAML
      - id: grouped_configurable_product
        query: "antrasit sineklik"
        expect:
          unique_products: true
          min_matching_variant_count: 2
          configuration_options_include: ["En", "Profil Rengi"]
          configuration_values_include:
            - name: "Profil Rengi"
              values: ["Antrasit", "Beyaz"]
          configuration_bounds:
            - name: "En"
              axis: width
              unit: cm
              max: 80
    YAML
    payload = {
      'result_type' => 'show_candidates',
      'candidates' => [
        candidate.merge(
          'product_id' => 'product-1',
          'matching_variant_count' => 2,
          'configuration' => {
            'options' => [
              { 'name' => 'En', 'type' => 'dimension', 'axis' => 'width', 'unit' => 'cm', 'max' => 80 },
              { 'name' => 'Profil Rengi', 'type' => 'choice', 'values' => %w[Antrasit Beyaz] }
            ]
          }
        )
      ]
    }

    with_cases(cases) do |path|
      evaluator, = evaluator_for(path, 'antrasit sineklik' => payload)

      expect(evaluator.evaluate.fetch('status')).to eq('passed')
    end
  end

  it 'reports clear failures for mismatched expectations' do
    cases = <<~YAML
      - id: missing_link
        query: "beyaz perde"
        expect:
          result_type: ["show_compatible_candidates"]
          min_results: 2
          first_result_include: ["Blackout"]
          top_results_include: ["Sineklik"]
          candidate_text_excludes: ["Antrasit"]
          require_links: true
          require_evidence:
            - fact: dimension_max
    YAML
    payload = {
      'result_type' => 'show_candidates',
      'parsed' => {},
      'candidates' => [
        candidate.merge('link' => {}),
        candidate.merge('display_name' => 'Blackout Perde Antrasit')
      ],
      'buckets' => []
    }

    with_cases(cases) do |path|
      evaluator, = evaluator_for(path, 'beyaz perde' => payload)
      report = evaluator.evaluate
      failures = report.dig('cases', 0, 'failures')

      expect(report.fetch('status')).to eq('failed')
      expect(failures).to include(
        'wrong_result_type: expected show_compatible_candidates, got show_candidates',
        'expected_text_not_found_in_first_result: blackout',
        'expected_text_not_found_in_top_results: sineklik',
        'excluded_text_found_in_candidates: antrasit',
        'missing_link'
      )
      expect(failures).to include('missing_evidence: fact=dimension_max')
    end
  end

  it 'renders reports as json and markdown' do
    report = {
      'status' => 'passed',
      'summary' => { 'total' => 1, 'passed' => 1, 'failed' => 0 },
      'cases' => [
        {
          'id' => 'case_1',
          'query' => 'perde',
          'status' => 'passed',
          'failures' => [],
          'result_type' => 'show_candidates',
          'candidate_count' => 1,
          'top_candidates' => [{ 'display_name' => 'Perde' }],
          'buckets' => [],
          'evidence' => []
        }
      ]
    }

    expect(JSON.parse(described_class.render(report, format: 'json')).fetch('status')).to eq('passed')
    expect(described_class.render(report, format: 'markdown')).to include('# Ikas Catalog Evaluation', '## PASS case_1')
  end

  it 'rejects malformed case files' do
    with_cases('id: not_an_array') do |path|
      evaluator, = evaluator_for(path, {})

      expect { evaluator.evaluate }.to raise_error(IkasCatalogMvp::Error, 'eval cases file must contain a YAML array')
    end
  end
end
