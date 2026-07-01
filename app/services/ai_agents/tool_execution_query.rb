# frozen_string_literal: true

class AiAgents::ToolExecutionQuery
  DEFAULT_LIMIT = 25
  MAX_LIMIT = 100
  DATE_RANGES = {
    '24h' => 24.hours,
    '7d' => 7.days,
    '30d' => 30.days
  }.freeze
  SORTS = {
    'created_at' => :created_at,
    'duration_ms' => :duration_ms,
    'status' => :status,
    'mode' => :mode,
    'tool_key' => :tool_key,
    'ai_agent_id' => :ai_agent_id
  }.freeze
  SUPER_ADMIN_SORTS = SORTS.merge('account_name' => 'accounts.name').freeze

  attr_reader :filters, :errors

  def initialize(scope:, params:, super_admin: false, strict_dates: false)
    @scope = scope
    @params = params
    @super_admin = super_admin
    @strict_dates = strict_dates
    @errors = []
    @filters = build_filters
  end

  def results
    filtered_scope.order(order_clause).limit(limit)
  end

  def valid?
    errors.blank?
  end

  private

  attr_reader :scope, :params

  def build_filters
    {
      status: permitted_status,
      mode: permitted_mode,
      tool_key: params[:tool_key].presence,
      date_range: permitted_date_range,
      start_date: parsed_start_date,
      end_date: parsed_end_date,
      sort: sort,
      direction: direction,
      limit: limit
    }
  end

  def filtered_scope
    executions = scope
    executions = executions.where(status: filters[:status]) if filters[:status].present?
    executions = executions.where(mode: filters[:mode]) if filters[:mode].present?
    executions = executions.where(tool_key: filters[:tool_key]) if filters[:tool_key].present?
    filter_by_dates(executions)
  end

  def permitted_status
    return unless params[:status].present? && AiAgentToolExecution.statuses.key?(params[:status])

    params[:status]
  end

  def permitted_mode
    return unless params[:mode].present? && AiAgentToolExecution.modes.key?(params[:mode])

    params[:mode]
  end

  def permitted_date_range
    return @permitted_date_range if defined?(@permitted_date_range)
    return @permitted_date_range = nil unless permitted_date_range_param?

    @permitted_date_range = params[:date_range]
  end

  def permitted_date_range_param?
    params[:date_range].present? && (DATE_RANGES.key?(params[:date_range]) || params[:date_range] == 'custom')
  end

  def parsed_start_date
    return unless permitted_date_range == 'custom'

    parse_time(:start_date)
  end

  def parsed_end_date
    return unless permitted_date_range == 'custom'

    params[:end_date].present? ? parse_time(:end_date) : Time.current
  end

  def parse_time(key)
    value = Time.zone.parse(params[key].to_s)
    errors << "#{key} is invalid" if value.blank? && @strict_dates
    value
  rescue ArgumentError, TypeError
    errors << "#{key} is invalid" if @strict_dates
    nil
  end

  def filter_by_dates(executions)
    return executions.where(created_at: DATE_RANGES.fetch(filters[:date_range]).ago..) if DATE_RANGES.key?(filters[:date_range])
    return filter_by_custom_dates(executions) if filters[:date_range] == 'custom'

    executions
  end

  def filter_by_custom_dates(executions)
    return executions if filters[:start_date].blank?
    return executions.where(created_at: filters[:start_date]..) if filters[:end_date].blank?

    executions.where(created_at: filters[:start_date]..filters[:end_date])
  end

  def sort
    sort_options.key?(params[:sort]) ? params[:sort] : 'created_at'
  end

  def direction
    params[:direction] == 'asc' ? 'asc' : 'desc'
  end

  def limit
    return DEFAULT_LIMIT if params[:limit].blank?

    params[:limit].to_i.clamp(1, MAX_LIMIT)
  end

  def order_clause
    { sort_options.fetch(sort) => direction }
  end

  def sort_options
    @super_admin ? SUPER_ADMIN_SORTS : SORTS
  end
end
