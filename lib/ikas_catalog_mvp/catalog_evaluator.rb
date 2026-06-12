# frozen_string_literal: true

require 'yaml'

module IkasCatalogMvp
  class CatalogEvaluator
    DEFAULT_FORMAT = 'markdown'
    TOP_CANDIDATE_LIMIT = 5
    FORMATS = %w[json markdown].freeze

    def initialize(sqlite_path:, cases_path:, limit: QueryEngine::DEFAULT_LIMIT, query_engine: nil)
      @sqlite_path = sqlite_path
      @cases_path = cases_path
      @limit = limit.to_i.positive? ? limit.to_i : QueryEngine::DEFAULT_LIMIT
      @query_engine = query_engine || QueryEngine.new(sqlite_path: sqlite_path)
    end

    def evaluate
      results = cases.map { |row| evaluate_case(row) }
      failed = results.count { |row| row.fetch('status') == 'failed' }
      {
        'status' => failed.zero? ? 'passed' : 'failed',
        'summary' => {
          'total' => results.length,
          'passed' => results.length - failed,
          'failed' => failed
        },
        'sqlite_path' => sqlite_path,
        'cases_path' => cases_path,
        'cases' => results
      }
    end

    def self.render(report, format: DEFAULT_FORMAT)
      format = format.to_s
      raise Error, "unsupported eval format: #{format}" unless FORMATS.include?(format)

      format == 'json' ? JSON.pretty_generate(report) : MarkdownRenderer.new(report).render
    end

    private

    attr_reader :sqlite_path, :cases_path, :limit, :query_engine

    def cases
      @cases ||= begin
        rows = YAML.safe_load(File.read(cases_path), aliases: false)
        raise Error, 'eval cases file must contain a YAML array' unless rows.is_a?(Array)

        rows.map.with_index { |row, index| normalize_case(row, index) }
      end
    rescue Psych::SyntaxError => e
      raise Error, "invalid eval cases YAML: #{e.message}"
    end

    def normalize_case(row, index)
      row = deep_stringify_keys(row)
      raise Error, "eval case ##{index + 1} must be a mapping" unless row.is_a?(Hash)
      raise Error, "eval case ##{index + 1} is missing id" if row['id'].to_s.empty?
      raise Error, "eval case #{row['id']} is missing query" if row['query'].to_s.empty?

      row['context_texts'] = Array(row['context_texts']).map(&:to_s)
      row['expect'] = deep_stringify_keys(row['expect'] || {})
      row
    end

    def evaluate_case(row)
      result = query_engine.query(row.fetch('query'), limit: limit, context_texts: row.fetch('context_texts'))
      result = deep_stringify_keys(result)
      failures = failures_for(row.fetch('expect'), result)

      {
        'id' => row.fetch('id'),
        'query' => row.fetch('query'),
        'context_texts' => row.fetch('context_texts'),
        'status' => failures.empty? ? 'passed' : 'failed',
        'failures' => failures,
        'result_type' => result['result_type'],
        'candidate_count' => candidates_for(result).length,
        'parsed' => result['parsed'],
        'top_candidates' => top_candidates_for(result),
        'buckets' => buckets_for(result),
        'evidence' => evidence_summary_for(result)
      }
    rescue StandardError => e
      {
        'id' => row.fetch('id'),
        'query' => row.fetch('query'),
        'context_texts' => row.fetch('context_texts'),
        'status' => 'failed',
        'failures' => ["query_error: #{e.class}: #{e.message}"],
        'result_type' => nil,
        'candidate_count' => 0,
        'parsed' => nil,
        'top_candidates' => [],
        'buckets' => [],
        'evidence' => []
      }
    end

    def failures_for(expectations, result)
      checks = []
      checks.concat(result_type_failures(expectations, result))
      checks.concat(min_result_failures(expectations, result))
      checks.concat(top_result_failures(expectations, result))
      checks.concat(link_failures(expectations, result))
      checks.concat(evidence_failures(expectations, result))
      checks.concat(bucket_failures(expectations, result))
      checks
    end

    def result_type_failures(expectations, result)
      expected = Array(expectations['result_type']).map(&:to_s)
      return [] if expected.empty? || expected.include?(result['result_type'].to_s)

      ["wrong_result_type: expected #{expected.join(' or ')}, got #{result['result_type']}"]
    end

    def min_result_failures(expectations, result)
      minimum = expectations['min_results']
      return [] unless minimum

      count = candidates_for(result).length
      count >= minimum.to_i ? [] : ["too_few_results: expected at least #{minimum}, got #{count}"]
    end

    def top_result_failures(expectations, result)
      expected = Array(expectations['top_results_include']).map { |value| Text.fold(value) }.reject(&:empty?)
      return [] if expected.empty?

      top_text = Text.fold(top_candidates_for(result).map { |candidate| candidate['display_name'] }.join(' '))
      expected.select { |value| !top_text.include?(value) }
              .map { |value| "expected_text_not_found_in_top_results: #{value}" }
    end

    def link_failures(expectations, result)
      return [] unless expectations['require_links']

      candidates = candidates_for(result)
      missing = candidates.select { |candidate| candidate.dig('link', 'url').to_s.empty? }
      return [] if candidates.any? && missing.empty?

      ['missing_link']
    end

    def evidence_failures(expectations, result)
      required = Array(expectations['require_evidence']).map { |row| deep_stringify_keys(row) }
      return [] if required.empty?

      evidence = candidates_for(result).flat_map { |candidate| Array(candidate['evidence']) }.map { |row| deep_stringify_keys(row) }
      required.filter_map do |expected|
        next if evidence.any? { |row| evidence_matches?(row, expected) }

        expected_label = expected.map { |key, value| "#{key}=#{value}" }.join(',')
        "missing_evidence: #{expected_label}"
      end
    end

    def evidence_matches?(actual, expected)
      expected.all? { |key, value| actual[key].to_s == value.to_s }
    end

    def bucket_failures(expectations, result)
      failures = []
      if expectations['min_buckets']
        count = buckets_for(result).length
        failures << "too_few_buckets: expected at least #{expectations['min_buckets']}, got #{count}" if count < expectations['min_buckets'].to_i
      end

      expected_labels = Array(expectations['bucket_labels_include']).map { |value| Text.fold(value) }.reject(&:empty?)
      bucket_text = Text.fold(bucket_labels_for(result).join(' '))
      failures.concat(expected_labels.select { |label| !bucket_text.include?(label) }.map { |label| "expected_bucket_not_found: #{label}" })
      failures
    end

    def candidates_for(result)
      Array(result['candidates'])
    end

    def buckets_for(result)
      Array(result['buckets'])
    end

    def bucket_labels_for(result)
      buckets_for(result).flat_map do |bucket|
        [bucket['label'], Array(bucket['children']).map { |child| child['label'] }]
      end.flatten.compact
    end

    def top_candidates_for(result)
      candidates_for(result).first(TOP_CANDIDATE_LIMIT).map do |candidate|
        {
          'display_name' => candidate['display_name'],
          'link_url' => candidate.dig('link', 'url'),
          'match_reasons' => Array(candidate['match_reasons'])
        }
      end
    end

    def evidence_summary_for(result)
      candidates_for(result).flat_map { |candidate| Array(candidate['evidence']) }.map do |row|
        row = deep_stringify_keys(row)
        row.slice('source', 'fact', 'key', 'value', 'confidence', 'match_kind')
      end.uniq
    end

    def deep_stringify_keys(value)
      case value
      when Hash
        value.to_h { |key, row_value| [key.to_s, deep_stringify_keys(row_value)] }
      when Array
        value.map { |row_value| deep_stringify_keys(row_value) }
      else
        value
      end
    end

    class MarkdownRenderer
      def initialize(report)
        @report = report
      end

      def render
        lines = []
        lines << '# Ikas Catalog Evaluation'
        lines << ''
        lines << "Status: **#{report.fetch('status').upcase}**"
        lines << "Cases: #{summary.fetch('passed')}/#{summary.fetch('total')} passed, #{summary.fetch('failed')} failed"
        lines << ''
        report.fetch('cases').each { |row| render_case(lines, row) }
        lines.join("\n")
      end

      private

      attr_reader :report

      def summary
        report.fetch('summary')
      end

      def render_case(lines, row)
        icon = row.fetch('status') == 'passed' ? 'PASS' : 'FAIL'
        lines << "## #{icon} #{row.fetch('id')}"
        lines << "- Query: `#{row.fetch('query')}`"
        lines << "- Result: `#{row['result_type'] || 'error'}` with #{row.fetch('candidate_count')} candidates"
        lines << "- Failures: #{row.fetch('failures').join('; ')}" if row.fetch('failures').any?
        lines << "- Top candidates: #{candidate_names(row)}" if row.fetch('top_candidates').any?
        lines << "- Buckets: #{bucket_names(row)}" if row.fetch('buckets').any?
        lines << "- Evidence: #{evidence_labels(row)}" if row.fetch('evidence').any?
        lines << ''
      end

      def candidate_names(row)
        row.fetch('top_candidates').map { |candidate| candidate.fetch('display_name') }.join(' | ')
      end

      def bucket_names(row)
        row.fetch('buckets').map do |bucket|
          child_labels = Array(bucket['children']).map { |child| child['label'] }
          child_labels.empty? ? bucket['label'] : "#{bucket['label']} (#{child_labels.join(', ')})"
        end.join(' | ')
      end

      def evidence_labels(row)
        row.fetch('evidence').map { |evidence| [evidence['fact'], evidence['source']].compact.join('@') }.uniq.join(', ')
      end
    end
  end
end
