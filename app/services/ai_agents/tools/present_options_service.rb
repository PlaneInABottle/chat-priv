# frozen_string_literal: true

class AiAgents::Tools::PresentOptionsService
  MIN_OPTIONS = 2
  MAX_OPTIONS = 10
  QUESTION_LIMIT = 1024
  GENERAL_LABEL_LIMIT = 72

  def initialize(tool_events: [], **_context)
    @tool_events = Array(tool_events)
  end

  def call(args:)
    args = args.to_h
    question = args['question'].to_s.strip
    return error_result('invalid_question') unless valid_question?(question)

    labels = option_labels(args)
    return labels if error_result?(labels)
    return error_result('invalid_options') unless valid_labels?(labels)

    {
      status: 'ok',
      terminal_action: AiAgents::Config::PRESENT_OPTIONS_TOOL,
      customer_message: question,
      presentation: {
        content_type: 'input_select',
        items: labels.map { |label| { title: label, value: SecureRandom.uuid } }
      }
    }
  end

  private

  attr_reader :tool_events

  def valid_question?(question)
    question.present? && question.length <= QUESTION_LIMIT
  end

  def option_labels(args)
    return error_result('invalid_option_source') unless exactly_one_option_source?(args)

    return catalog_labels(args['catalog_option_ids']) if args.key?('catalog_option_ids')

    general_labels(args['options'])
  end

  def error_result?(result)
    result.is_a?(Hash) && result[:status] == 'error'
  end

  def exactly_one_option_source?(args)
    args.key?('options') ^ args.key?('catalog_option_ids')
  end

  def general_labels(options)
    labels = Array(options).filter_map { |option| option['label'].to_s.strip if option.is_a?(Hash) }
    return error_result('invalid_options') unless labels.length == Array(options).length
    return error_result('invalid_options') unless labels.all? { |label| label.present? && label.length <= GENERAL_LABEL_LIMIT }

    labels
  end

  def catalog_labels(option_ids)
    ids = Array(option_ids).map { |id| id.to_s.strip }
    return error_result('invalid_options') unless valid_catalog_ids?(ids)

    available_options = latest_catalog_options
    return error_result('catalog_evidence_required') if available_options.empty?
    return error_result('unknown_catalog_option') unless ids.all? { |id| available_options.key?(id) }

    ids.map { |id| available_options.fetch(id) }
  end

  def valid_catalog_ids?(ids)
    valid_option_count?(ids) && ids.all?(&:present?) && ids.uniq.length == ids.length
  end

  def latest_catalog_options
    result = latest_catalog_event&.dig('result')
    return {} unless result.is_a?(Hash)

    extract_catalog_options(result)
  end

  def latest_catalog_event
    tool_events.reverse.find do |event|
      event['tool'] == AiAgents::Config::IKAS_CATALOG_SEARCH_TOOL && event['status'].to_s == 'ok'
    end
  end

  def extract_catalog_options(result)
    options = {}
    Array(result['buckets']).each do |bucket|
      add_catalog_option(options, bucket['category_id'], bucket['label'])
      Array(bucket['children']).each { |child| add_catalog_option(options, child['category_id'], child['label']) }
    end
    Array(result['candidates']).each do |candidate|
      next if candidate.dig('stock', 'sellable') == false

      add_catalog_option(options, candidate['item_id'], candidate['display_name'])
    end
    Array(result['queries']).each { |child_result| options.merge!(extract_catalog_options(child_result)) }
    options
  end

  def add_catalog_option(options, id, label)
    id = id.to_s.strip
    label = label.to_s.strip
    options[id] = label if id.present? && label.present?
  end

  def valid_labels?(labels)
    valid_option_count?(labels) && labels.map(&:downcase).uniq.length == labels.length
  end

  def valid_option_count?(values)
    values.length.between?(MIN_OPTIONS, MAX_OPTIONS)
  end

  def error_result(error_code)
    {
      status: 'error',
      error_code: error_code,
      error_message: 'Options could not be presented safely.',
      recoverable: true
    }
  end
end
