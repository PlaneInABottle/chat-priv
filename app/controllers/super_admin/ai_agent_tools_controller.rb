class SuperAdmin::AiAgentToolsController < SuperAdmin::ApplicationController
  def index
    @tool_definitions = AiAgents::ToolRegistry.available_definitions
    @account_filter_options = Account.order(:name).pluck(:name, :id)
    @analytics = analytics_scope.group(:status).count
    @recent_executions = analytics_scope.includes(:account, :conversation).order(created_at: :desc).limit(25)
  end

  def show
    @tool_definition = AiAgents::ToolRegistry.find(params[:id])
    return head :not_found unless @tool_definition

    @source_code = service_source(@tool_definition)
  end

  private

  def analytics_scope
    scope = AiAgentToolExecution.all
    scope = scope.where(account_id: params[:account_id]) if params[:account_id].present?
    scope
  end

  def service_source(tool_definition)
    klass = tool_definition.service_class.constantize
    source_path = klass.instance_method(:call).source_location&.first
    return unless source_path

    path = Pathname.new(source_path).realpath
    return unless path.to_s.start_with?(Rails.root.join('app').to_s)

    path.read
  rescue NameError, Errno::ENOENT
    nil
  end
end
